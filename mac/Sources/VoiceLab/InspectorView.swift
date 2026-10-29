import SwiftUI

/// The right-hand panel: the chosen voice, how it reads, blending, pronunciations and the clips folder.
struct InspectorView: View {
    @Environment(Studio.self) private var studio

    var body: some View {
        @Bindable var studio = studio
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                CurrentVoice()

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    ValueRow(title: "Speed", value: String(format: "%.2f×", studio.settings.speed))
                    Slider(value: stepped($studio.settings.speed, 0.05), in: 0.5...1.5)
                    HStack {
                        Text("Slower")
                        Spacer()
                        Button("Normal") { studio.settings.speed = 1 }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                            .help("Back to normal speed")
                        Spacer()
                        Text("Faster")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    ValueRow(title: "Pause after each sentence", value: String(format: "%.2f s", studio.settings.pause))
                    Slider(value: stepped($studio.settings.pause, 0.05), in: 0...1)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Blend with another voice").fontWeight(.semibold)
                    Picker("Blend with another voice", selection: $studio.settings.mixVoice) {
                        Text("No blend").tag("")
                        ForEach(studio.blendGroups) { g in
                            Section(g.name) {
                                ForEach(g.voices) { v in Text(v.name).tag(v.id) }
                            }
                        }
                    }
                    .labelsHidden()
                    if let m = studio.blendVoice {
                        HStack(spacing: 10) {
                            Slider(value: stepped($studio.settings.mix, 0.05), in: 0.05...0.7)
                                .accessibilityLabel("How much of the second voice")
                            Text("\(Int((studio.settings.mix * 100).rounded()))% \(m.name)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .frame(minWidth: 86, alignment: .trailing)
                        }
                    }
                }

                Divider()

                Pronunciations()

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Clips folder").fontWeight(.semibold)
                    Text(studio.prettyPath(studio.outDir))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Button("Change…") { studio.changeFolder() }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                }
            }
            .padding(18)
        }
    }

    private func stepped(_ b: Binding<Double>, _ step: Double) -> Binding<Double> {
        Binding(get: { b.wrappedValue }, set: { b.wrappedValue = ($0 / step).rounded() * step })
    }
}

private struct ValueRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).fontWeight(.semibold)
            Spacer()
            Text(value).foregroundStyle(.secondary).monospacedDigit()
        }
    }
}

private struct CurrentVoice: View {
    @Environment(Studio.self) private var studio

    var body: some View {
        let on = studio.playing == .sample(studio.settings.voice)
        VStack(alignment: .leading, spacing: 2) {
            Text(studio.currentGroupLabel)
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(studio.currentVoice?.name ?? " ")
                .font(.system(size: 34, weight: .medium, design: .serif))
            if let m = studio.blendVoice {
                Text("blended with \(m.name)")
                    .font(.system(.title3, design: .serif))
                    .italic()
                    .foregroundStyle(.secondary)
            }
            Button {
                Task { await studio.playSample(studio.settings.voice, blend: studio.blendVoice != nil) }
            } label: {
                if studio.loadingSample == studio.settings.voice {
                    Label("Getting a sample…", systemImage: "hourglass")
                } else {
                    Label(on ? "Stop" : "Hear a sample", systemImage: on ? "stop.fill" : "play.fill")
                }
            }
            .buttonStyle(.glass)
            .tint(Brand.red)
            .padding(.top, 10)
            .disabled(studio.currentVoice == nil)
        }
    }
}

private struct Pronunciations: View {
    @Environment(Studio.self) private var studio

    var body: some View {
        @Bindable var studio = studio
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Pronunciation").fontWeight(.semibold)
                Spacer()
                Button("Add a word", systemImage: "plus") {
                    studio.lexicon.append(Word(word: "", say: ""))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Brand.red)
            }
            Text("For names the voice says wrong. Write how it sounds (ee-kwate), or give exact sounds between slashes.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach($studio.lexicon) { $w in
                HStack(spacing: 6) {
                    TextField("Word", text: $w.word)
                        .textFieldStyle(.roundedBorder)
                    TextField("Say it as", text: $w.say)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .serif))
                    Button { Task { await studio.testWord(w) } } label: {
                        Image(systemName: studio.playing == .word(w.id) ? "speaker.wave.2.fill" : "play.fill")
                    }
                    .buttonStyle(.borderless)
                    .help("Hear it")
                    Button { studio.lexicon.removeAll { $0.id == w.id } } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove")
                }
            }
        }
    }
}
