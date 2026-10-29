import SwiftUI

@main
struct VoiceLabApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var studio = Studio()

    var body: some Scene {
        Window("VoiceLab", id: "main") {
            ContentView()
                .environment(studio)
                .frame(minWidth: 1120, minHeight: 640)
                .task { await studio.boot() }
        }
        .defaultSize(width: 1320, height: 840)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Clip") {
                Button(studio.makeLabel) { Task { await studio.make() } }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!studio.canMake)
                Button(studio.playing == nil ? "Play Latest Clip" : "Stop") {
                    if studio.playing != nil { studio.stop() } else if let t = studio.takes.first { studio.togglePlay(t) }
                }
                .keyboardShortcut("l", modifiers: .command)
                .disabled(studio.takes.isEmpty && studio.playing == nil)
                Divider()
                Button("Show Clips in Finder") { studio.revealFolder() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                Button("Change Clips Folder…") { studio.changeFolder() }
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) { Engine.shared.stop() }
}
