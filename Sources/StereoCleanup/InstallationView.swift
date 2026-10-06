import SwiftUI
import AppKit

struct InstallationView: View {
    @ObservedObject var model: AppModel
    @State private var copied = ""
    private let installer = #"/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)""#
    #if arch(arm64)
    private let shellenv = #"eval "$(/opt/homebrew/bin/brew shellenv)""#
    #else
    private let shellenv = #"eval "$(/usr/local/bin/brew shellenv)""#
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Install FFmpeg", systemImage: "wrench.and.screwdriver")
                .font(.title2.weight(.semibold))
            Text("Run these commands in Terminal, one at a time. This app does not install software or ask for your password.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            step("1. Install Homebrew", detail: "Skip this step if Homebrew is already installed.", command: installer)
            step("2. Make Homebrew available", detail: "After installation, follow Homebrew’s printed Next steps. This command enables it in the current Terminal window.", command: shellenv)
            step("3. Install FFmpeg", detail: "This installs both ffmpeg and ffprobe. Wait until it finishes.", command: "brew install ffmpeg")
            HStack {
                Link("Homebrew website", destination: URL(string: "https://brew.sh/")!)
                Text("·").foregroundStyle(.secondary)
                Link("FFmpeg formula", destination: URL(string: "https://formulae.brew.sh/formula/ffmpeg")!)
                Spacer()
                Button("Open Terminal") {
                    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") {
                        NSWorkspace.shared.openApplication(at: url, configuration: .init())
                    }
                }
            }.font(.callout)
            Divider()
            HStack {
                Text(model.installStatus.isEmpty ? "Then return here and click Check Again." : model.installStatus)
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Close") { model.showInstallHelp = false }.keyboardShortcut(.cancelAction)
                Button("Check Again", action: model.checkTools).keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }.padding(26).frame(width: 680)
    }

    private func step(_ title: String, detail: String, command: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.headline)
            Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 10) {
                Text(command).font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(copied == command ? "Copied" : "Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                    copied = command
                }.controlSize(.small)
            }.padding(12).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
