import SwiftUI
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    weak var model: AppModel?
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model, model.busy else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Stop processing and quit?"
        alert.informativeText = "The current temporary file will be discarded. Completed outputs and all originals will remain untouched."
        alert.addButton(withTitle: "Stop and Quit"); alert.addButton(withTitle: "Keep Processing")
        guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }
        model.onIdle = { NSApp.reply(toApplicationShouldTerminate: true) }
        model.stop()
        return .terminateLater
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let model, model.busy else { return true }
        let alert = NSAlert()
        alert.messageText = "Processing is still running"
        alert.informativeText = "Stop safely before closing this window?"
        alert.addButton(withTitle: "Keep Processing"); alert.addButton(withTitle: "Stop and Close")
        if alert.runModal() == .alertSecondButtonReturn {
            model.onIdle = { sender.close() }
            model.stop()
        }
        return false
    }
}

@main
struct SteFiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = AppModel()
    var body: some Scene {
        Window("SteFi", id: "main") {
            ContentView(model: model)
                .onAppear {
                    delegate.model = model
                    DispatchQueue.main.async {
                        NSApp.windows.first { $0.title == "SteFi" }?.delegate = delegate
                        model.begin()
                    }
                }
        }
        .defaultSize(width: 1080, height: 740)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Another Folder…", action: model.chooseFolder)
                    .keyboardShortcut("o", modifiers: []).disabled(model.busy)
                Button("Rescan", action: model.scan)
                    .keyboardShortcut("r", modifiers: []).disabled(model.busy || model.folder == nil || model.tools == nil)
            }
        }
    }
}
