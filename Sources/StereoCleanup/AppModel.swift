import SwiftUI
import AppKit
import StereoCore

struct MovieRow: Identifiable {
    var candidate: MediaCandidate
    var checked = false
    var state = "Ready"
    var error: String?
    var output: URL?
    var id: String { candidate.id }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var folder: URL?
    @Published var rows: [MovieRow] = []
    @Published var busy = false
    @Published var scanning = false
    @Published var cancelling = false
    @Published var status = "Choose a folder to get started."
    @Published var fraction = 0.0
    @Published var logText = ""
    @Published var showLog = false
    @Published var inspected = 0
    @Published var alreadyReady = 0
    @Published var showInstallHelp = false
    @Published var installStatus = ""
    @Published var statistics = ProcessingStats()
    @Published var processingPhase: ProcessingPhase = .processing
    @Published var currentDuration = 0.0
    @Published var currentNumber = 0
    @Published var totalJobs = 0
    @Published var jobStarted: Date?
    @Published var jobFinished: Date?
    @Published var activeJobID: String?
    @Published var lastJobOutcome = ""
    @Published var tools: ToolPaths? = ToolPaths.discover(custom: UserDefaults.standard.string(forKey: "ToolDirectory"))
    private var token: CancellationToken?
    private var activeTask: Task<Void, Never>?
    private var prompted = false
    var onIdle: (() -> Void)?

    var pending: [MovieRow] { rows.filter { $0.output == nil } }
    var selected: [MovieRow] { pending.filter(\.checked) }
    var copyCount: Int { pending.filter { AudioPolicy.canCopy($0.candidate.selected) }.count }

    func begin() {
        // Hosted Xcode unit tests must not present interactive folder/tool panels.
        guard NSClassFromString("XCTestCase") == nil,
              ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        guard !prompted else { return }
        prompted = true
        NSApp.activate(ignoringOtherApps: true)
        if tools == nil { missingToolsAlert() }
        else { chooseFolder() }
    }

    func missingToolsAlert() {
        let panel = NSAlert()
        panel.messageText = "FFmpeg is not installed"
        panel.informativeText = "SteFi needs ffmpeg and ffprobe installed on this Mac. View the Homebrew installation guide, including how to install Homebrew itself. Nothing will be installed automatically."
        panel.alertStyle = .warning
        panel.addButton(withTitle: "Installation Guide")
        panel.addButton(withTitle: "Later")
        if panel.runModal() == .alertFirstButtonReturn { showInstallHelp = true }
    }

    func checkTools() {
        tools = ToolPaths.discover(custom: UserDefaults.standard.string(forKey: "ToolDirectory"))
        guard tools != nil else {
            installStatus = "Not found yet. Complete the commands in Terminal, then check again."
            return
        }
        installStatus = "FFmpeg and ffprobe found."
        showInstallHelp = false
        status = "FFmpeg is ready. Choose a video folder."
        // Let the installation sheet dismiss before presenting a folder panel.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            if folder == nil { chooseFolder() } else { scan() }
        }
    }

    func chooseFolder() {
        guard !busy else { return }
        guard tools != nil else { missingToolsAlert(); return }
        let panel = NSOpenPanel()
        panel.title = "Choose the folder containing your videos"
        panel.prompt = "Scan Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = folder
        if panel.runModal() == .OK, let url = panel.url { folder = url; scan() }
    }

    func chooseTools() {
        guard !busy else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose a folder containing ffmpeg and ffprobe"
        panel.message = "Both executables must be in this folder. Homebrew tools are normally in /opt/homebrew/bin."
        panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.directoryURL = URL(fileURLWithPath: "/opt/homebrew/bin")
        if panel.runModal() == .OK, let url = panel.url {
            let candidate = ToolPaths(directory: url)
            if candidate.available {
                UserDefaults.standard.set(url.path, forKey: "ToolDirectory")
                tools = candidate
                if folder != nil { scan() }
            } else { alert("FFmpeg tools not found", "This folder must contain executable files named ffmpeg and ffprobe.") }
        }
    }

    func scan() {
        guard !busy, let folder else { return }
        guard let tools else {
            status = "FFmpeg and ffprobe are missing. Open the installation guide."
            missingToolsAlert()
            return
        }
        rows = []; inspected = 0; alreadyReady = 0; fraction = 0; logText = ""; showLog = false
        jobStarted = nil; jobFinished = nil; activeJobID = nil
        busy = true; scanning = true; cancelling = false
        status = "Scanning this folder only…"
        let cancellation = CancellationToken()
        token = cancellation
        let engine = CleanupEngine(tools: tools)
        activeTask = Task { [self] in
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try engine.scan(folder, token: cancellation) { name, current, total in
                        Task { @MainActor [weak self] in
                            self?.status = "Scanning \(current)/\(total): \(name)"
                            self?.fraction = Double(current) / Double(max(1, total))
                        }
                    }
                }.value
                rows = result.candidates.map { MovieRow(candidate: $0) }
                inspected = result.inspected; alreadyReady = result.ready
                status = "\(rows.count) need cleanup · \(alreadyReady) already have one suitable stereo track"
                if !result.warnings.isEmpty {
                    appendLog(result.warnings.joined(separator: "\n") + "\n")
                    status += " · \(result.warnings.count) unreadable / no-audio files (see log)"
                    showLog = true
                }
            } catch {
                status = error.localizedDescription
                appendLog(status + "\n")
            }
            finish()
        }
    }

    func selectAll(_ value: Bool) {
        for i in rows.indices where rows[i].output == nil { rows[i].checked = value }
    }

    func run(all: Bool) {
        guard !busy, let tools else { return }
        let jobs = (all ? pending : selected).map(\.candidate)
        guard !jobs.isEmpty else { return }
        let mkv = jobs.filter(\.requiresMKV)
        let warnings = jobs.filter(\.warning)
        var message = "Each output will contain exactly one audio track. All other audio tracks are removed from the NEW file only. Originals and existing outputs are never overwritten."
        if !warnings.isEmpty {
            message += "\n\nCHECK THE AUDIO LANGUAGE: \(warnings.count) selection(s) differ from the source's default audio track:\n"
            message += warnings.prefix(6).map { "• \($0.url.lastPathComponent): \($0.selected.label)" }.joined(separator: "\n")
        }
        if !mkv.isEmpty {
            message += "\n\nAAC cannot be stored in these original containers. Start approves .st.mkv instead for:\n"
            message += mkv.prefix(6).map { "• \($0.url.lastPathComponent) → \($0.outputURL.lastPathComponent)" }.joined(separator: "\n")
        }
        let panel = NSAlert()
        panel.messageText = "Process \(jobs.count) video\(jobs.count == 1 ? "" : "s")?"
        panel.informativeText = message
        panel.alertStyle = (!warnings.isEmpty || !mkv.isEmpty) ? .warning : .informational
        panel.addButton(withTitle: "Start"); panel.addButton(withTitle: "Cancel")
        guard panel.runModal() == .alertFirstButtonReturn else { return }
        let cancellation = CancellationToken(), engine = CleanupEngine(tools: tools)
        token = cancellation; busy = true; scanning = false; cancelling = false; fraction = 0
        totalJobs = jobs.count
        activeTask = Task { [self] in
            var completed = 0, failed = 0
            // Prevent idle system sleep during an active conversion; closing the
            // laptop or manually sleeping the Mac can still suspend the work.
            let activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled], reason: "Converting selected video audio")
            defer { ProcessInfo.processInfo.endActivity(activity) }
            for (position, job) in jobs.enumerated() {
                if cancellation.isCancelled { break }
                status = "\(position + 1)/\(jobs.count) · \(job.url.lastPathComponent)"
                currentNumber = position + 1; currentDuration = job.probe.duration
                statistics = ProcessingStats(); processingPhase = .processing
                activeJobID = job.id; jobStarted = Date(); jobFinished = nil
                lastJobOutcome = "Processing"
                setState(job.id, "Processing…")
                do {
                    let output = try await Task.detached(priority: .userInitiated) {
                        try engine.convert(job, allowMKV: true, token: cancellation,
                            progress: { value in
                                Task { @MainActor [weak self] in
                                    guard self?.activeJobID == job.id else { return }
                                    self?.fraction = (Double(position) + value) / Double(jobs.count)
                                }
                            }, statistics: { stats in
                                Task { @MainActor [weak self] in
                                    guard self?.activeJobID == job.id else { return }
                                    self?.statistics = stats
                                }
                            }, phase: { phase in
                                Task { @MainActor [weak self] in
                                    guard self?.activeJobID == job.id else { return }
                                    self?.processingPhase = phase
                                }
                            }, log: { text in
                                Task { @MainActor [weak self] in self?.appendLog(text) }
                            })
                    }.value
                    if let index = rows.firstIndex(where: { $0.id == job.id }) {
                        rows[index].output = output; rows[index].state = "Created & verified"
                        rows[index].checked = false; rows[index].error = nil
                    }
                    completed += 1
                    lastJobOutcome = "Created & verified"
                } catch {
                    let text = error.localizedDescription
                    lastJobOutcome = cancellation.isCancelled ? "Cancelled" : "Skipped / failed"
                    setState(job.id, cancellation.isCancelled ? "Cancelled" : "Skipped / failed", error: text)
                    appendLog(text + "\n")
                    showLog = true
                    if cancellation.isCancelled { break }
                    failed += 1
                }
            }
            if cancellation.isCancelled { status = "Stopped · \(completed) created. Originals untouched." }
            else { fraction = 1; status = "Done · \(completed) created · \(failed) skipped / failed" }
            finish()
        }
    }

    func stop() { cancelling = true; status = "Stopping safely…"; token?.cancel() }
    private func finish() {
        if jobStarted != nil { jobFinished = Date() }
        activeJobID = nil
        busy = false; scanning = false; cancelling = false; token = nil; activeTask = nil
        let action = onIdle; onIdle = nil; action?()
    }
    private func setState(_ id: String, _ value: String, error: String? = nil) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[index].state = value; rows[index].error = error
    }
    func appendLog(_ value: String) {
        logText += value
        if logText.count > 120_000 { logText = String(logText.suffix(100_000)) }
    }
    func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    func saveLog() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "SteFi.log"
        if panel.runModal() == .OK, let url = panel.url {
            do { try logText.write(to: url, atomically: true, encoding: .utf8) }
            catch { alert("Could not save log", error.localizedDescription) }
        }
    }
    private func alert(_ title: String, _ message: String) {
        let a = NSAlert(); a.messageText = title; a.informativeText = message; a.runModal()
    }
}
