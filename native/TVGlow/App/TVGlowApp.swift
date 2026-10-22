import SwiftUI

@main
@MainActor
struct TVGlowApp: App {
    @StateObject private var store = ControlStore()
    @StateObject private var remote = AppleRemoteStore()

    var body: some Scene {
        #if os(macOS)
        Window("TV Glow", id: "main") {
            ContentView(store: store, remote: remote)
                .frame(minWidth: 380, idealWidth: 440, maxWidth: 520, minHeight: 640, idealHeight: 800)
        }
        .defaultSize(width: 440, height: 800)
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Reconnect TV") { Task { await store.connectTV() } }.keyboardShortcut("r", modifiers: [.command])
                Button("Refresh devices") { Task { await store.refresh() } }.keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }
        MenuBarExtra {
            MenuControlsView(store: store, remote: remote)
        } label: {
            Image(systemName: "sun.max")
        }
        .menuBarExtraStyle(.window)
        #else
        WindowGroup {
            ContentView(store: store, remote: remote)
        }
        #endif
    }
}
