import SwiftUI

/// The middle of the window: the script on top, the clips below, both on Liquid Glass over the red glow.
struct DeskView: View {
    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 14) {
                ScriptCard()
                    .frame(height: max(250, geo.size.height * 0.44))
                ClipsCard()
            }
            .padding(16)
        }
        .background { Backdrop() }
    }
}

// MARK: - Script

struct ScriptCard: View {
    @Environment(Studio.self) private var studio
    @FocusState private var focused: Bool

    private let scriptFont = Font.system(size: 21, design: .serif)

    var body: some View {
        @Bindable var studio = studio
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                if studio.script.isEmpty {
                    Text("Type or paste what you want said.")
                        .font(scriptFont).italic()
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 29)
                        .padding(.top, 24)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $studio.script)
                    .font(scriptFont)
                    .lineSpacing(6)
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(.never)  // the scroll bar track showed as a tall glass pill on the panel
                    .focused($focused)
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
            }
            MakeBar()
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
        }
        .glassPanel(tint: 0.42)
        .onChange(of: studio.focusScript) { focused = true }
        .onAppear { if studio.script.isEmpty { focused = true } }
    }
}

struct MakeBar: View {
    @Environment(Studio.self) private var studio

    var body: some View {
        @Bindable var studio = studio
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 14) {
                Picker("How to cut the script", selection: $studio.settings.split) {
                    Text("One clip").tag(false)
                    Text("A clip per line").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("A clip per line makes a separate file for every line of the script")

                Text(studio.estimate)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)

                Spacer(minLength: 8)

                Button { Task { await studio.make() } } label: {
                    HStack(spacing: 8) {
                        if studio.busy {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "waveform")
                        }
                        Text(studio.makeLabel).fontWeight(.semibold)
                        Text("⌘↵").font(.caption).opacity(0.75)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                }
                .buttonStyle(.glassProminent)
                .tint(Brand.red)
                .controlSize(.large)
                .disabled(!studio.canMake)
            }
        }
    }
}

// MARK: - Clips

struct ClipsCard: View {
    @Environment(Studio.self) private var studio

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Clips").font(.headline)
                if !studio.takes.isEmpty {
                    Text("\(studio.takes.count)").foregroundStyle(.secondary).monospacedDigit()
                }
                Spacer()
                Button("Show in Finder", systemImage: "folder") { studio.revealFolder() }
                    .buttonStyle(.glass)
                    .controlSize(.small)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)

            if let e = studio.error, !studio.ready {
                Label(e, systemImage: "exclamationmark.triangle.fill")
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Brand.red.opacity(0.14), in: .rect(cornerRadius: 14))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }

            if studio.takes.isEmpty && !studio.busy {
                EmptyClips()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if studio.busy { PendingRow() }
                        ForEach(studio.takes) { t in
                            TakeRow(take: t)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 16)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .glassPanel()
    }
}

struct EmptyClips: View {
    @Environment(Studio.self) private var studio

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Each clip you make lands here and is saved as a WAV file in your clips folder.")
            Button(studio.prettyPath(studio.outDir)) { studio.revealFolder() }
                .buttonStyle(.link)
            Text("Tip: “A clip per line” turns a whole script into separate files, one per line, ready for your edit.")
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: 560, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }
}

struct PendingRow: View {
    @Environment(Studio.self) private var studio

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "record.circle")
                .font(.title2)
                .foregroundStyle(Brand.red)
                .symbolEffect(.pulse)
                .frame(width: 34)
            Text(studio.pendingLabel)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 8)
    }
}

struct TakeRow: View {
    let take: Take
    @Environment(Studio.self) private var studio
    @State private var hover = false
    @State private var editing = false
    @State private var draft = ""
    @FocusState private var titleFocused: Bool

    private var isPlaying: Bool { studio.playing == .take(take.id) }
    private var saidMore: Bool { take.text.count > take.title.replacingOccurrences(of: "…", with: "").count + 2 }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            PlayButton(on: isPlaying) { studio.togglePlay(take) }
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    if editing {
                        TextField("Title", text: $draft)
                            .textFieldStyle(.plain)
                            .fontWeight(.semibold)
                            .focused($titleFocused)
                            .onAppear { titleFocused = true }
                            .onSubmit { commitRename() }
                            .onExitCommand { editing = false }
                            .onChange(of: titleFocused) { if !titleFocused && editing { commitRename() } }
                    } else {
                        Text(take.title)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                            .onTapGesture { draft = take.title; editing = true }
                            .help("Click to rename")
                    }
                    Spacer(minLength: 8)
                    Text(fmtSecs(take.seconds))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                GeometryReader { geo in
                    TimelineView(.animation(paused: !isPlaying)) { _ in
                        Waveform(peaks: take.peaks, progress: studio.progress(of: take), active: isPlaying)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(coordinateSpace: .local) { loc in
                        studio.seek(take, to: max(0, min(1, loc.x / max(geo.size.width, 1))))
                    }
                }
                .frame(height: 34)

                HStack(spacing: 6) {
                    Text(studio.meta(for: take))
                        .foregroundStyle(.secondary)
                    if saidMore {
                        Text("“\(take.text)”")
                            .font(.system(.callout, design: .serif))
                            .italic()
                            .foregroundStyle(.secondary)
                            .truncationMode(.tail)
                    }
                    Spacer(minLength: 8)
                    if hover {
                        HStack(spacing: 2) {
                            Button("Use again") { studio.reuse(take) }
                            Button("Show in Finder") { studio.reveal(take) }
                            Button("Delete", role: .destructive) { Task { await studio.delete(take) } }
                        }
                        .buttonStyle(.borderless)
                        .transition(.opacity)
                    }
                }
                .font(.callout)
                .lineLimit(1)
                .help(take.text)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 10)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(studio.freshIDs.contains(take.id) ? Brand.red.opacity(0.12) : (hover ? Color.primary.opacity(0.045) : .clear))
        }
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }
        .contextMenu {
            Button(isPlaying ? "Stop" : "Play") { studio.togglePlay(take) }
            Button("Rename") { draft = take.title; editing = true }
            Button("Use Again") { studio.reuse(take) }
            Button("Show in Finder") { studio.reveal(take) }
            Divider()
            Button("Move to Bin", role: .destructive) { Task { await studio.delete(take) } }
        }
    }

    private func commitRename() {
        guard editing else { return }
        editing = false
        let title = draft
        Task { await studio.rename(take, to: title) }
    }
}

struct PlayButton: View {
    let on: Bool
    let action: () -> Void

    var body: some View {
        Group {
            if on {
                Button(action: action) {
                    Image(systemName: "pause.fill").frame(width: 16, height: 16)
                }
                .buttonStyle(.glassProminent)
                .tint(Brand.red)
            } else {
                Button(action: action) {
                    Image(systemName: "play.fill").frame(width: 16, height: 16)
                }
                .buttonStyle(.glass)
            }
        }
        .buttonBorderShape(.circle)
        .accessibilityLabel(on ? "Pause" : "Play")
    }
}

struct Waveform: View {
    let peaks: [Double]
    let progress: Double
    let active: Bool

    var body: some View {
        Canvas { ctx, size in
            guard !peaks.isEmpty, size.width > 3 else { return }
            let step: CGFloat = 3
            let n = Int(size.width / step)
            for i in 0..<n {
                let f = Double(i) / Double(n)
                let v = peaks[min(peaks.count - 1, Int(f * Double(peaks.count)))]
                let h = max(1.5, CGFloat(pow(max(v, 0), 0.8)) * (size.height - 2))
                let bar = CGRect(x: CGFloat(i) * step, y: (size.height - h) / 2, width: 2, height: h)
                let color = active && f <= progress ? Brand.red : Color.primary.opacity(0.22)
                ctx.fill(Path(roundedRect: bar, cornerRadius: 1), with: .color(color))
            }
        }
    }
}
