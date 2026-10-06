import SwiftUI
import StereoCore

struct ContentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if model.tools == nil {
                ContentUnavailableView {
                    Label("FFmpeg tools needed", systemImage: "wrench.and.screwdriver")
                } description: {
                    Text("Install FFmpeg on your Mac using Homebrew. The guide also explains how to install Homebrew if you do not have it yet.")
                } actions: {
                    Button("Installation Guide…") { model.showInstallHelp = true }
                    Button("Check Again", action: model.checkTools)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.rows.isEmpty {
                ContentUnavailableView {
                    Label(model.scanning ? "Scanning videos…" : (model.folder == nil ? "One folder. One stereo track." : "Nothing to clean up"),
                          systemImage: model.scanning ? "waveform" : "waveform.circle")
                } description: {
                    Text(model.folder == nil ? "Choose a folder. Videos and subtitles stay untouched; only audio is cleaned up."
                         : "Only this folder is scanned, never its subfolders. Files with one suitable stereo track are left alone.")
                } actions: {
                    if !model.busy { Button("Choose Folder…", action: model.chooseFolder) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, row in
                        movieRow(index: index, row: row)
                    }
                }
                .listStyle(.inset)
            }
            if !model.logText.isEmpty {
                Divider()
                DisclosureGroup(isExpanded: $model.showLog) {
                    ScrollView {
                        Text(model.logText).font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(8)
                    }
                    .frame(height: 150).background(.background)
                    HStack { Spacer(); Button("Save Log…", action: model.saveLog).controlSize(.small) }
                } label: { Label("Processing log", systemImage: "text.alignleft").font(.callout) }
                .padding(.horizontal, 20).padding(.vertical, 8)
            }
            Divider()
            footer
        }
        .frame(minWidth: 920, minHeight: 610)
        .sheet(isPresented: $model.showInstallHelp) { InstallationView(model: model) }
        .toolbar {
            ToolbarItemGroup {
                Menu {
                    Button("FFmpeg Installation Guide…") { model.showInstallHelp = true }
                    Button("Choose FFmpeg Tools…", action: model.chooseTools)
                    if let tools = model.tools {
                        Text(tools.ffmpeg.deletingLastPathComponent().path)
                    }
                } label: { Image(systemName: "gearshape") }.disabled(model.busy)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Image(nsImage: NSApplication.shared.applicationIconImage).resizable().frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text("SteFi").font(.system(size: 26, weight: .semibold))
                    Text(model.folder?.path ?? "AAC 320 kb/s when needed · Original sample rate")
                        .font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Label("Originals protected", systemImage: "lock.shield").font(.callout.weight(.medium))
                    Text("No overwriting. No subfolders.").font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 10) {
                Button(action: model.chooseFolder) { Label("Open Another Folder (O)", systemImage: "folder") }
                    .keyboardShortcut("o", modifiers: []).disabled(model.busy)
                    .help("Open another video folder — O (no Command key)")
                Button(action: model.scan) { Label("Rescan (R)", systemImage: "arrow.clockwise") }
                    .keyboardShortcut("r", modifiers: []).disabled(model.busy || model.folder == nil || model.tools == nil)
                    .help("Rescan this folder and clear the selection — R (no Command key)")
                Spacer()
                Text("Select files to process").font(.caption).foregroundStyle(.secondary)
            }
            if !model.rows.isEmpty {
                HStack(spacing: 18) {
                    Label("\(model.pending.count) need cleanup", systemImage: "film")
                    Text("\(model.copyCount) copy stereo · \(model.pending.count - model.copyCount) encode AAC").foregroundStyle(.secondary)
                    Spacer()
                    Button("Select All") { model.selectAll(true) }.keyboardShortcut("a")
                    Button("Clear") { model.selectAll(false) }
                }.font(.callout).disabled(model.busy)
            }
        }.padding(20)
    }

    private func movieRow(index: Int, row: MovieRow) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Toggle("Select \(row.candidate.url.lastPathComponent)", isOn: $model.rows[index].checked)
                .labelsHidden().toggleStyle(.checkbox).disabled(model.busy || row.output != nil).padding(.top, 3)
            Text("\(index + 1)").monospacedDigit().foregroundStyle(.secondary).frame(width: 24, alignment: .trailing).padding(.top, 3)
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    Text(row.candidate.url.lastPathComponent).font(.headline).lineLimit(2).textSelection(.enabled)
                    Spacer()
                    Text(AudioPolicy.canCopy(row.candidate.selected) ? "COPY STEREO" : "AAC 320k")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(AudioPolicy.canCopy(row.candidate.selected) ? Color.green.opacity(0.13) : Color.orange.opacity(0.13), in: Capsule())
                }
                Picker("Keep audio", selection: $model.rows[index].candidate.selectedIndex) {
                    ForEach(row.candidate.probe.audio) { stream in Text(stream.label).tag(stream.index) }
                }
                .pickerStyle(.menu).disabled(model.busy || row.output != nil)
                if row.candidate.warning {
                    Label("Not the original default audio — check language and title.", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
                HStack {
                    Text("→ \(row.candidate.outputURL.lastPathComponent)").lineLimit(1).truncationMode(.middle)
                    if row.candidate.requiresMKV && row.output == nil { Text("MKV approval required").foregroundStyle(.orange) }
                    Spacer()
                    if let output = row.output { Button("Show in Finder") { model.reveal(output) }.buttonStyle(.link) }
                    Text(row.state).foregroundStyle(row.error == nil ? Color.secondary : .red)
                }.font(.caption)
                if let error = row.error { Text(error).font(.caption).foregroundStyle(.red).lineLimit(3).textSelection(.enabled) }
            }
        }.padding(.vertical, 10)
            .accessibilityElement(children: .contain)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            if model.scanning { ProgressView(value: model.fraction).progressViewStyle(.linear) }
            else if model.jobStarted != nil { ProcessingView(model: model) }
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.status).font(.callout).lineLimit(2)
                    Text("Output: name.st.ext · Exactly one audio track · Video & subtitles copied")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if model.busy {
                    Button(model.cancelling ? "Stopping…" : "Stop", action: model.stop).disabled(model.cancelling)
                } else {
                    Button("Process All (0)") { model.run(all: true) }
                        .keyboardShortcut("0", modifiers: []).disabled(model.pending.isEmpty)
                    Button("Process Selected (\(model.selected.count))") { model.run(all: false) }
                        .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).disabled(model.selected.isEmpty)
                        .help("Process only checked files — Enter / Return")
                }
            }
        }.padding(20)
    }
}
