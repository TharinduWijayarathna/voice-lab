import AppKit
import AVFoundation
import SwiftUI

enum Playing: Equatable {
    case take(String), sample(String), word(UUID)
}

struct VoiceGroup: Identifiable {
    let name: String
    let voices: [Voice]
    var id: String { name }
}

/// Everything the window shows, and everything it can do.
@MainActor @Observable
final class Studio {
    var voices: [Voice] = []
    var takes: [Take] = []
    var settings = StudioSettings()
    var lexicon: [Word] = []
    var ready = false
    var error: String?
    var outDir = ""
    var home = NSHomeDirectory()

    var script = ""
    var voiceQuery = ""
    var busy = false
    var pendingLabel = ""
    var playing: Playing?
    var loadingSample: String?
    var toast: String?
    var freshIDs: Set<String> = []
    var focusScript = 0

    @ObservationIgnored private var player: AVAudioPlayer?
    private let playerDelegate = PlayerDelegate()
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var lexiconTask: Task<Void, Never>?
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var loaded = false
    let engine = Engine.shared

    init() {
        playerDelegate.onFinish = { [weak self] in
            Task { @MainActor in self?.playing = nil }
        }
    }

    // MARK: Starting up

    func boot() async {
        do { try await engine.start() } catch {
            self.error = error.localizedDescription
            return
        }
        while true {
            if let st: EngineState = try? await engine.get("api/state") {
                voices = st.voices
                ready = st.ready
                error = st.error
                outDir = st.outDir
                home = st.home
                if !loaded {
                    loaded = true
                    settings = st.settings
                    lexicon = st.lexicon
                    takes = st.takes
                    if script.isEmpty { script = st.settings.draft }
                }
                if st.ready || st.error != nil { return }
            }
            try? await Task.sleep(for: .milliseconds(400))
        }
    }

    // MARK: Saving

    func saveSettings() {
        guard loaded else { return }
        saveTask?.cancel()
        let s = settings
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            if Task.isCancelled { return }
            _ = try? await engine.post("api/settings", s) as EngineState
        }
    }

    func saveLexicon() {
        guard loaded else { return }
        lexiconTask?.cancel()
        let entries = lexicon
        lexiconTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            if Task.isCancelled { return }
            do { let _: OKReply = try await engine.post("api/lexicon", LexiconBody(entries: entries)) } catch { show(error.localizedDescription) }
        }
    }

    // MARK: Voices

    func voice(_ id: String) -> Voice? { voices.first { $0.id == id } }
    var currentVoice: Voice? { voice(settings.voice) }
    var blendVoice: Voice? {
        settings.mixVoice.isEmpty || settings.mixVoice == settings.voice ? nil : voice(settings.mixVoice)
    }
    var currentGroupLabel: String {
        guard let g = currentVoice?.group else { return " " }
        if g.hasSuffix("women") { return String(g.dropLast(5)) + "woman" }
        if g.hasSuffix("men") { return String(g.dropLast(3)) + "man" }
        return g
    }

    private func grouped(_ list: [Voice]) -> [VoiceGroup] {
        var out: [VoiceGroup] = []
        for v in list {
            if let i = out.firstIndex(where: { $0.name == v.group }) {
                out[i] = VoiceGroup(name: v.group, voices: out[i].voices + [v])
            } else {
                out.append(VoiceGroup(name: v.group, voices: [v]))
            }
        }
        return out
    }

    var voiceGroups: [VoiceGroup] {
        let q = voiceQuery.trimmingCharacters(in: .whitespaces).lowercased()
        return grouped(q.isEmpty ? voices : voices.filter { $0.name.lowercased().contains(q) || $0.group.lowercased().contains(q) })
    }

    var blendGroups: [VoiceGroup] { grouped(voices.filter { $0.id != settings.voice }) }

    func pickVoice(_ id: String) {
        settings.voice = id
        if settings.mixVoice == id { settings.mixVoice = "" }
    }

    func playSample(_ id: String, blend: Bool = false) async {
        if playing == .sample(id) { stop(); return }
        loadingSample = id
        defer { loadingSample = nil }
        do {
            let body = SampleBody(voice: id, mixVoice: blend ? settings.mixVoice : "", mix: blend ? settings.mix : 0)
            let r: PathReply = try await engine.post("api/sample", body)
            play(URL(fileURLWithPath: r.path), as: .sample(id))
        } catch { show(error.localizedDescription) }
    }

    // MARK: Playback

    func play(_ url: URL, as who: Playing, from fraction: Double = 0) {
        player?.stop()
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = playerDelegate
            p.prepareToPlay()
            if fraction > 0 { p.currentTime = fraction * p.duration }
            p.play()
            player = p
            playing = who
        } catch {
            show("Couldn't play that: \(error.localizedDescription)")
        }
    }

    func stop() {
        player?.stop()
        playing = nil
    }

    func progress(of take: Take) -> Double {
        guard playing == .take(take.id), let p = player, p.duration > 0 else { return 0 }
        return p.currentTime / p.duration
    }

    func clipURL(_ t: Take) -> URL { URL(fileURLWithPath: outDir).appending(path: t.file) }

    func togglePlay(_ t: Take) {
        if playing == .take(t.id) { stop() } else { play(clipURL(t), as: .take(t.id)) }
    }

    func seek(_ t: Take, to f: Double) {
        if playing == .take(t.id), let p = player {
            p.currentTime = f * p.duration
            if !p.isPlaying { p.play() }
        } else {
            play(clipURL(t), as: .take(t.id), from: f)
        }
    }

    // MARK: Making clips

    var pieces: [String] {
        let lines = script.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if settings.split { return lines }
        return lines.isEmpty ? [] : [lines.joined(separator: " ")]
    }

    var canMake: Bool { ready && !busy && !pieces.isEmpty }

    var makeLabel: String {
        if !ready { return error != nil ? "Voice model missing" : "Loading the voice…" }
        if busy { return "Speaking…" }
        let n = pieces.count
        return settings.split && n > 1 ? "Make \(n) clips" : "Make clip"
    }

    var estimate: String {
        let words = script.split(whereSeparator: \.isWhitespace).count
        guard words > 0 else { return "" }
        let chars = Array(script)
        var sentences = 0
        for i in chars.indices where ".!?".contains(chars[i]) {
            let next: Character = i + 1 < chars.count ? chars[i + 1] : " "
            if next.isWhitespace { sentences += 1 }
        }
        let secs = Double(words) / 2.75 / max(settings.speed, 0.1) + Double(sentences) * settings.pause
        var s = "\(words) \(words == 1 ? "word" : "words"), about \(fmtSecs(secs))"
        if settings.split, pieces.count > 1 { s += " · \(pieces.count) lines" }
        return s
    }

    func make() async {
        guard canMake else { return }
        let ps = pieces
        busy = true
        stop()
        var made = 0
        defer { busy = false; pendingLabel = "" }
        do {
            for (i, piece) in ps.enumerated() {
                pendingLabel = ps.count > 1 ? "Line \(i + 1) of \(ps.count): \(piece)" : "Speaking: \(piece)"
                let body = SpeakBody(text: piece, voice: settings.voice, speed: settings.speed, pause: settings.pause,
                                     mixVoice: settings.mixVoice, mix: settings.mix, split: false, at: made)
                let r: TakesReply = try await engine.post("api/speak", body)
                withAnimation(.snappy) {
                    for t in r.takes {
                        takes.insert(t, at: min(made, takes.count))
                        freshIDs.insert(t.id)
                        made += 1
                    }
                }
            }
            if made == 1, let t = takes.first { play(clipURL(t), as: .take(t.id)) }
            else if made > 1 { show("\(made) clips saved in \(prettyPath(outDir)).") }
        } catch {
            show(error.localizedDescription)
        }
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation(.easeOut(duration: 0.6)) { freshIDs.removeAll() }
        }
    }

    // MARK: Clips

    func meta(for t: Take) -> String {
        var bits = [voice(t.voice)?.name ?? t.voice]
        if let m = t.mixVoice, !m.isEmpty { bits.append("+ \(voice(m)?.name ?? m) \(Int(((t.mix ?? 0) * 100).rounded()))%") }
        if abs(t.speed - 1) > 0.001 { bits.append(String(format: "%.2f× speed", t.speed)) }
        return bits.joined(separator: "  ")
    }

    func rename(_ t: Take, to title: String) async {
        let v = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.isEmpty, v != t.title else { return }
        do {
            let r: TakeReply = try await engine.post("api/rename", RenameBody(id: t.id, title: v))
            if let i = takes.firstIndex(where: { $0.id == t.id }) { takes[i] = r.take }
            show("Renamed to “\(r.take.file)”")
        } catch { show(error.localizedDescription) }
    }

    func reuse(_ t: Take) {
        script = t.text
        settings.voice = t.voice
        settings.speed = t.speed
        settings.pause = t.pause ?? 0.25
        settings.mixVoice = t.mixVoice ?? ""
        if let m = t.mix, m > 0 { settings.mix = m }
        focusScript += 1
        show("Script and settings from “\(t.title)” are back in the editor.")
    }

    func delete(_ t: Take) async {
        if playing == .take(t.id) { stop() }
        // Into the Bin the way Finder does it, so "Put Back" works.
        try? FileManager.default.trashItem(at: clipURL(t), resultingItemURL: nil)
        do {
            let _: OKReply = try await engine.post("api/delete", IDBody(id: t.id))
            withAnimation(.snappy) { takes.removeAll { $0.id == t.id } }
            show("Moved “\(t.file)” to the Bin.")
        } catch { show(error.localizedDescription) }
    }

    func reveal(_ t: Take) {
        NSWorkspace.shared.activateFileViewerSelecting([clipURL(t)])
    }

    func revealFolder() {
        guard !outDir.isEmpty else { return }
        let url = URL(fileURLWithPath: outDir, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }

    func changeFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use This Folder"
        panel.directoryURL = URL(fileURLWithPath: outDir)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        saveTask?.cancel()
        var s = settings
        s.outDir = url.path
        let snapshot = s
        Task {
            do {
                let st: EngineState = try await engine.post("api/settings", snapshot)
                settings = st.settings
                outDir = st.outDir
                takes = st.takes
                show("New clips will be saved in \(prettyPath(st.outDir)).")
            } catch { show(error.localizedDescription) }
        }
    }

    // MARK: Pronunciation

    func testWord(_ w: Word) async {
        guard !w.word.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        do {
            let r: PathReply = try await engine.post("api/test-word", TestWordBody(word: w.word, say: w.say, voice: settings.voice))
            play(URL(fileURLWithPath: r.path), as: .word(w.id))
        } catch { show(error.localizedDescription) }
    }

    // MARK: Little things

    var subtitle: String {
        if let e = error, !e.isEmpty, !ready { return "Voice model missing" }
        if !ready { return "Loading the voice…" }
        return takes.isEmpty ? "No clips yet" : "\(takes.count) \(takes.count == 1 ? "clip" : "clips")"
    }

    func prettyPath(_ p: String) -> String {
        var s = p
        if s.hasPrefix(home) { s = "~" + String(s.dropFirst(home.count)) }
        if s.hasPrefix("~/") { s = String(s.dropFirst(2)) }
        return s.replacingOccurrences(of: "/", with: " › ")
    }

    func show(_ message: String) {
        toastTask?.cancel()
        withAnimation(.snappy) { toast = message }
        toastTask = Task {
            try? await Task.sleep(for: .seconds(2.8))
            if Task.isCancelled { return }
            withAnimation(.easeOut) { toast = nil }
        }
    }
}

final class PlayerDelegate: NSObject, AVAudioPlayerDelegate {
    var onFinish: (() -> Void)?
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { onFinish?() }
}

func fmtSecs(_ s: Double) -> String {
    if s < 59.95 { return String(format: "%.1f s", s) }
    let t = Int(s.rounded())
    return String(format: "%d:%02d", t / 60, t % 60)
}
