import FreeroomCore
import SwiftUI

/// Last stop before anything is removed: shows exactly what will happen, requires an explicit check.
struct ConfirmSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var reviewed = false
    @State private var items: [Finding] = []
    @State private var started = false
    @State private var freeBefore: Int64 = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(started ? (model.cleaning ? "Cleaning…" : "Done") : "Review before cleaning")
                .font(.title2.weight(.semibold))

            if started && !model.cleaning {
                doneSummary
            }

            List(items) { finding in
                HStack(alignment: .top, spacing: 10) {
                    statusIcon(finding)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(finding.title).font(.body.weight(.medium))
                        Text(what(finding)).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                        if let outcome = model.cleanResults[finding.id], case .skipped(let reason) = outcome {
                            Text("Skipped: \(reason)").font(.caption).foregroundStyle(.secondary)
                        }
                        if let outcome = model.cleanResults[finding.id], case .failed(let reason) = outcome {
                            Text("Failed: \(reason)").font(.caption).foregroundStyle(Theme.danger)
                        }
                    }
                    Spacer()
                    Text(finding.sizeBytes.formattedBytes).monospacedDigit()
                }
            }
            .frame(minHeight: 220)

            if !started {
                Toggle("I reviewed these items and commands", isOn: $reviewed)
                Text("Safe items are deleted; Review items go to the Trash. Commands run only if they are on Freeroom's allowlist.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                if started {
                    Button("Close") { dismiss() }.disabled(model.cleaning).keyboardShortcut(.defaultAction)
                } else {
                    Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                    Button("Clean \(totalBytes.formattedBytes)") {
                        freeBefore = model.freeBytes
                        started = true
                        model.clean(items, origin: "app")
                    }
                    .buttonStyle(.borderedProminent).tint(Theme.accent)
                    .disabled(!reviewed)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(width: 620, height: 520)
        .onAppear { items = model.selectedFindings }
    }

    private var totalBytes: Int64 { items.reduce(0) { $0 + $1.sizeBytes - $1.sharedBytes } }

    private var doneSummary: some View {
        let freed = items.reduce(Int64(0)) { $0 + (model.cleanResults[$1.id]?.freedBytes ?? 0) }
        return HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.safe)
            Text("Freed about \(freed.formattedBytes): \(freeBefore.formattedBytes) → \(model.freeBytes.formattedBytes) free")
                .monospacedDigit()
        }
        .font(.headline)
    }

    @ViewBuilder
    private func statusIcon(_ finding: Finding) -> some View {
        switch model.cleanResults[finding.id] {
        case .cleaned: Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.safe)
        case .skipped: Image(systemName: "minus.circle").foregroundStyle(.secondary)
        case .failed: Image(systemName: "xmark.octagon.fill").foregroundStyle(Theme.danger)
        case nil:
            if started { ProgressView().controlSize(.small) } else { SafetyBadge(safety: finding.safety) }
        }
    }

    private func what(_ f: Finding) -> String {
        switch f.action {
        case .command: (f.needsAdmin ? "needs admin · " : "") + (f.command ?? "")
        case .trash: "Move to Trash: " + f.paths.prefix(2).map { PathUtils.abbreviate($0) }.joined(separator: ", ") + (f.paths.count > 2 ? " …" : "")
        case .delete: "Delete: " + f.paths.prefix(2).map { PathUtils.abbreviate($0) }.joined(separator: ", ") + (f.paths.count > 2 ? " … (\(f.paths.count) paths)" : "")
        case .none: "nothing to run"
        }
    }
}
