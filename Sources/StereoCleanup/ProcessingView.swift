import SwiftUI
import StereoCore

struct ProcessingView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let stats = model.statistics
            let elapsed = (model.jobFinished ?? context.date).timeIntervalSince(model.jobStarted ?? context.date)
            let fileFraction = stats.fraction(duration: model.currentDuration)
            let finished = !model.busy && model.lastJobOutcome == "Created & verified"
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("File \(model.currentNumber) of \(model.totalJobs)", systemImage: "waveform.path")
                        .font(.callout.weight(.semibold))
                    Text(model.busy ? model.processingPhase.rawValue : model.lastJobOutcome)
                        .font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(time(stats.seconds)) / \(time(model.currentDuration > 0 ? model.currentDuration : nil))")
                        .font(.callout.monospacedDigit())
                    Text(fileFraction == nil ? "—" : String(format: "%.1f%%", (finished ? 1 : min(0.99, fileFraction!)) * 100))
                        .font(.callout.weight(.semibold).monospacedDigit()).frame(width: 64, alignment: .trailing)
                }
                ProgressView(value: finished ? 1 : min(0.99, fileFraction ?? 0))
                    .help("Current file. Completion includes checking the output before saving it.")
                HStack(alignment: .top, spacing: 16) {
                    metric("FPS", value: positive(stats.fps, suffix: ""),
                           note: stats.frame.map { "\($0.formatted()) frames" } ?? "No frames reported")
                        .help("FFmpeg's processing frames per second, not the movie's frame rate. Stream copy may report zero or no FPS.")
                    metric("Speed", value: positive(stats.speed, suffix: "×"), note: "relative to real time")
                    metric("Elapsed", value: time(max(0, elapsed)), note: "this file")
                    metric("Remaining", value: finished ? "00:00" : (model.busy && model.processingPhase == .processing ? time(stats.remaining(duration: model.currentDuration)) : "—"),
                           note: "estimate · this file")
                        .help("Based on remaining media duration and FFmpeg's current speed. Final verification may take additional time.")
                    metric("Output size", value: stats.bytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "—",
                           note: "written so far")
                }
                HStack {
                    Text("Batch progress").foregroundStyle(.secondary)
                    ProgressView(value: model.fraction).frame(maxWidth: 160)
                    Text(String(format: "%.0f%%", model.fraction * 100)).monospacedDigit().foregroundStyle(.secondary)
                    Spacer()
                    Text("Live FFmpeg statistics").foregroundStyle(.tertiary)
                }.font(.caption)
            }.padding(16)
                .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary, lineWidth: 1))
        }
    }

    private func metric(_ title: String, value: String, note: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit())
            Text(note).font(.system(size: 10)).foregroundStyle(.tertiary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func positive(_ value: Double?, suffix: String) -> String {
        guard let value, value.isFinite, value > 0 else { return "—" }
        return String(format: "%.1f", value) + suffix
    }
    private func time(_ value: Double?) -> String {
        guard let value, value.isFinite, value >= 0, value < 3_155_760_000 else { return "—" }
        let seconds = Int(value)
        if seconds >= 3600 { return String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60) }
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
