import SwiftUI

struct ContentView: View {
    @Environment(Studio.self) private var studio
    @State private var showInspector = true

    var body: some View {
        @Bindable var studio = studio
        NavigationSplitView {
            VoiceSidebar()
                .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 320)
        } detail: {
            DeskView()
        }
        .searchable(text: $studio.voiceQuery, placement: .sidebar, prompt: "Find a voice")
        .inspector(isPresented: $showInspector) {
            InspectorView()
                .inspectorColumnWidth(min: 270, ideal: 300, max: 380)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { studio.revealFolder() } label: {
                    Label("Show in Finder", systemImage: "folder")
                }
                .help("Show the clips folder in Finder")
            }
            ToolbarItem(placement: .primaryAction) {
                Button { showInspector.toggle() } label: {
                    Label("Sound", systemImage: "slider.horizontal.3")
                }
                .help(showInspector ? "Hide sound settings" : "Show sound settings")
            }
        }
        .navigationTitle("VoiceLab")
        .navigationSubtitle(studio.subtitle)
        .tint(Brand.red)
        .overlay(alignment: .bottom) { ToastView() }
        .onChange(of: studio.settings) { studio.saveSettings() }
        .onChange(of: studio.lexicon) { studio.saveLexicon() }
        .onChange(of: studio.script) { studio.settings.draft = studio.script }
    }
}

// MARK: - Voices

struct VoiceSidebar: View {
    @Environment(Studio.self) private var studio

    var body: some View {
        let selection = Binding<String?>(
            get: { studio.settings.voice },
            set: { if let id = $0 { studio.pickVoice(id) } }
        )
        List(selection: selection) {
            if studio.voices.isEmpty {
                Text(studio.error == nil ? "Loading voices…" : "No voices yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(studio.voiceGroups) { group in
                Section(group.name) {
                    ForEach(group.voices) { v in
                        VoiceRow(voice: v).tag(v.id as String?)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if !studio.voices.isEmpty, studio.voiceGroups.isEmpty {
                ContentUnavailableView.search(text: studio.voiceQuery)
            }
        }
    }
}

struct VoiceRow: View {
    let voice: Voice
    @Environment(Studio.self) private var studio
    @State private var hover = false

    var body: some View {
        let on = studio.playing == .sample(voice.id)
        let loading = studio.loadingSample == voice.id
        HStack(spacing: 8) {
            Text(voice.name).fontWeight(.medium)
            if voice.best {
                Text("Most natural").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if hover || on || loading {
                Button { Task { await studio.playSample(voice.id) } } label: {
                    if loading {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: on ? "stop.fill" : "play.fill").font(.caption)
                    }
                }
                .buttonStyle(.borderless)
                .help("Hear \(voice.name)")
                .accessibilityLabel("Hear \(voice.name)")
            }
        }
        .contentShape(Rectangle())
        .onHover { hover = $0 }
    }
}

// MARK: - Toast

struct ToastView: View {
    @Environment(Studio.self) private var studio

    var body: some View {
        if let t = studio.toast {
            Text(t)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .glassEffect(.regular, in: .capsule)
                .padding(.bottom, 26)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
