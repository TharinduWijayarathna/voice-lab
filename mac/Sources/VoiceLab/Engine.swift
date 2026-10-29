import Foundation

// MARK: - What the engine sends back

struct Voice: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let group: String
    let lang: String
    let gender: String
    let best: Bool
}

struct Take: Codable, Identifiable, Hashable {
    let id: String
    var file: String
    var title: String
    var text: String
    var voice: String
    var mixVoice: String?
    var mix: Double?
    var speed: Double
    var pause: Double?
    var seconds: Double
    var peaks: [Double]
}

struct StudioSettings: Codable, Equatable {
    var voice = "af_heart"
    var speed = 1.0
    var pause = 0.25
    var mixVoice = ""
    var mix = 0.3
    var split = false
    var outDir = ""
    var draft = ""
}

struct Word: Codable, Identifiable, Hashable {
    var id = UUID()
    var word: String
    var say: String
    enum CodingKeys: String, CodingKey { case word, say }
}

struct EngineState: Decodable {
    let ready: Bool
    let error: String?
    let voices: [Voice]
    let settings: StudioSettings
    let lexicon: [Word]
    let takes: [Take]
    let outDir: String
    let home: String
}

struct TakesReply: Decodable { let takes: [Take] }
struct TakeReply: Decodable { let take: Take }
struct PathReply: Decodable { let path: String }
struct OKReply: Decodable { let ok: Bool }
private struct ErrorReply: Decodable { let error: String }

// MARK: - What the app sends

struct SpeakBody: Encodable { let text, voice: String; let speed, pause: Double; let mixVoice: String; let mix: Double; let split: Bool; let at: Int }
struct SampleBody: Encodable { let voice, mixVoice: String; let mix: Double }
struct TestWordBody: Encodable { let word, say, voice: String }
struct RenameBody: Encodable { let id, title: String }
struct IDBody: Encodable { let id: String }
struct LexiconBody: Encodable { let entries: [Word] }

struct EngineError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

// MARK: - The engine process

/// Starts `engine/server.py` with VoiceLab's private Python and talks to it over 127.0.0.1.
/// The server quits by itself when this app goes away, because it watches its stdin.
final class Engine: @unchecked Sendable {
    static let shared = Engine()

    private var process: Process?
    private var stdinPipe: Pipe?
    private var logHandle: FileHandle?
    private(set) var baseURL: URL?

    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 900
        c.timeoutIntervalForResource = 3600
        return URLSession(configuration: c)
    }()
    private let decoder: JSONDecoder = { let d = JSONDecoder(); d.keyDecodingStrategy = .convertFromSnakeCase; return d }()
    private let encoder: JSONEncoder = { let e = JSONEncoder(); e.keyEncodingStrategy = .convertToSnakeCase; return e }()

    static var supportDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support/VoiceLab")
    }

    private var pythonURL: URL {
        if let p = ProcessInfo.processInfo.environment["VOICELAB_PYTHON"] { return URL(fileURLWithPath: p) }
        return Self.supportDir.appending(path: "venv/bin/python")
    }

    /// Inside the app: Contents/Resources/engine/server.py. Run from the source folder (Xcode, swift run): ../engine/server.py.
    private var serverURL: URL? {
        let fm = FileManager.default
        if let p = ProcessInfo.processInfo.environment["VOICELAB_ENGINE"] { return URL(fileURLWithPath: p) }
        if let r = Bundle.main.resourceURL?.appending(path: "engine/server.py"), fm.fileExists(atPath: r.path) { return r }
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // VoiceLab
            .deletingLastPathComponent()  // Sources
            .deletingLastPathComponent()  // mac
            .deletingLastPathComponent()  // the repo
        let dev = repo.appending(path: "engine/server.py")
        return fm.fileExists(atPath: dev.path) ? dev : nil
    }

    private final class Startup { var buffer = Data(); var done = false; let lock = NSLock() }

    func start() async throws {
        if baseURL != nil { return }
        let py = pythonURL
        guard FileManager.default.isExecutableFile(atPath: py.path) else {
            throw EngineError("VoiceLab's voice engine isn't set up yet. Double-click install.command in the VoiceLab folder.")
        }
        guard let server = serverURL else {
            throw EngineError("VoiceLab can't find its voice engine. Run install.command again.")
        }
        try? FileManager.default.createDirectory(at: Self.supportDir, withIntermediateDirectories: true)
        let logURL = Self.supportDir.appending(path: "log.txt")
        if !FileManager.default.fileExists(atPath: logURL.path) { FileManager.default.createFile(atPath: logURL.path, contents: nil) }
        logHandle = try? FileHandle(forWritingTo: logURL)
        _ = try? logHandle?.seekToEnd()

        let p = Process()
        p.executableURL = py
        p.arguments = ["-u", server.path, "--watch-stdin"]
        var env = ProcessInfo.processInfo.environment
        env["PYTHONUNBUFFERED"] = "1"
        p.environment = env
        let input = Pipe(), output = Pipe()
        p.standardInput = input
        p.standardOutput = output
        p.standardError = logHandle ?? FileHandle.nullDevice
        stdinPipe = input
        process = p

        let st = Startup()
        let log = logHandle
        let failed = EngineError("VoiceLab's voice engine stopped while starting. The details are in ~/Library/Application Support/VoiceLab/log.txt.")
        let port: Int = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Int, Error>) in
            output.fileHandleForReading.readabilityHandler = { h in
                let chunk = h.availableData
                st.lock.lock(); defer { st.lock.unlock() }
                if chunk.isEmpty { h.readabilityHandler = nil }
                if st.done { if !chunk.isEmpty { log?.write(chunk) }; return }
                if chunk.isEmpty { st.done = true; cont.resume(throwing: failed); return }
                st.buffer.append(chunk)
                guard let text = String(data: st.buffer, encoding: .utf8),
                      let r = text.range(of: #"VOICELAB_PORT=\d+\n"#, options: .regularExpression) else { return }
                let n = Int(text[r].filter(\.isNumber)) ?? 0
                st.done = true
                cont.resume(returning: n)
            }
            p.terminationHandler = { _ in
                st.lock.lock(); defer { st.lock.unlock() }
                if !st.done { st.done = true; cont.resume(throwing: failed) }
            }
            do { try p.run() } catch {
                st.lock.lock(); defer { st.lock.unlock() }
                if !st.done { st.done = true; cont.resume(throwing: EngineError("Couldn't start VoiceLab's voice engine: \(error.localizedDescription)")) }
            }
        }
        baseURL = URL(string: "http://127.0.0.1:\(port)/")
    }

    func stop() {
        process?.terminate()
        process = nil
        baseURL = nil
    }

    // MARK: Requests

    func get<T: Decodable>(_ path: String) async throws -> T {
        try await send(path, data: nil)
    }

    func post<T: Decodable, B: Encodable>(_ path: String, _ body: B) async throws -> T {
        try await send(path, data: try encoder.encode(body))
    }

    private func send<T: Decodable>(_ path: String, data: Data?) async throws -> T {
        guard let base = baseURL else { throw EngineError("The voice engine isn't running yet.") }
        var req = URLRequest(url: base.appending(path: path))
        if let data {
            req.httpMethod = "POST"
            req.httpBody = data
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let reply: Data, response: URLResponse
        do { (reply, response) = try await session.data(for: req) } catch {
            throw EngineError("VoiceLab's voice engine isn't responding. Quit VoiceLab and open it again.")
        }
        if let code = (response as? HTTPURLResponse)?.statusCode, code >= 400 {
            throw EngineError((try? decoder.decode(ErrorReply.self, from: reply))?.error ?? "Something went wrong.")
        }
        return try decoder.decode(T.self, from: reply)
    }
}
