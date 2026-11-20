import FreeroomCore
import SwiftUI

/// One sheet, three phases: review (grouped by what will happen) → cleaning → "You freed".
struct CleanSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State var items: [Finding]
    @State private var phase: Phase = .review
    @State private var freeBefore: Int64 = 0
    @State private var shownFreed: Double = 0
    @State private var glints = false

    enum Phase { case review, cleaning, done }

    init(items: [Finding]) { _items = State(initialValue: items) }

    private var total: Int64 { items.reduce(0) { $0 + $1.reclaimable } }
    private var freed: Int64 { items.reduce(0) { $0 + (model.cleanResults[$1.id]?.freedBytes ?? 0) } }

    var body: some View {
        VStack(spacing: 0) {
            switch phase {
            case .review, .cleaning: reviewOrCleaning
            case .done: done
            }
        }
        .frame(width: 600, height: 560)
        .onAppear { freeBefore = model.freeBytes }
        .onChange(of: model.cleaning) { _, cleaning in
            if !cleaning && phase == .cleaning {
                withAnimation(.spring(duration: 0.5)) { phase = .done }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 1.3)) { shownFreed = Double(freed) }
                withAnimation(.spring(duration: 0.6).delay(0.3)) { glints = true }
            }
        }
        .onChange(of: freed) { _, value in
            if phase == .cleaning { withAnimation(.smooth) { shownFreed = Double(value) } }
        }
    }

    // MARK: Review + cleaning

    private var reviewOrCleaning: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(phase == .review ? (items.count == 1 ? L("Clean 1 item") : String(format: L("Clean %@ items"), "\(items.count)")) : L("Cleaning…"))
                        .font(.fr(.title2).weight(.semibold))
                    Text("\(L("Free space")) \(freeBefore.formattedBytes) → \((freeBefore + total).formattedBytes)")
                        .foregroundStyle(.secondary).monospacedDigit()
                }
                Spacer()
                Text(phase == .review ? total.formattedBytes : Int64(shownFreed).formattedBytes)
                    .font(.system(size: FontScale.size(34), weight: .semibold, design: .rounded)).monospacedDigit()
                    .contentTransition(.numericText(value: phase == .review ? Double(total) : shownFreed))
                    .foregroundStyle(phase == .cleaning ? Theme.safe : .primary)
            }
            DiskBar(total: model.totalBytes, free: freeBefore, safe: 0, review: 0, keep: 0, incoming: total)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    group(.delete, title: L("Delete"), subtitle: L("regenerable"), symbol: "xmark.bin")
                    group(.command, title: L("Run cleanup command"), subtitle: L("the tool's own command"), symbol: "terminal")
                    group(.trash, title: L("Move to Trash"), subtitle: L("recoverable"), symbol: "trash")
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield").foregroundStyle(Theme.accent)
                Text(L("Review items go to the Trash. Commands run only if allowlisted. Each item is re-checked first."))
                    .font(.fr(.caption)).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button(L("Cancel")) { model.finishClean() }
                    .keyboardShortcut(.cancelAction).disabled(phase == .cleaning)
                Button(phase == .review ? String(format: L("Clean %@"), total.formattedBytes) : L("Cleaning…")) {
                    phase = .cleaning
                    model.clean(items, origin: "app")
                }
                .buttonStyle(.borderedProminent).tint(Theme.accent)
                .keyboardShortcut(.defaultAction)
                .disabled(phase == .cleaning || items.isEmpty)
            }
        }
        .padding(22)
    }

    @ViewBuilder
    private func group(_ action: CleanupAction, title: String, subtitle: String, symbol: String) -> some View {
        let groupItems = items.filter { $0.action == action }
        if !groupItems.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: symbol).foregroundStyle(Theme.accent)
                    Text(title).font(.fr(.headline))
                    Text("· \(subtitle)").foregroundStyle(.secondary)
                    Spacer()
                    Text(groupItems.reduce(Int64(0)) { $0 + $1.reclaimable }.formattedBytes).monospacedDigit().foregroundStyle(.secondary)
                }
                ForEach(groupItems) { finding in
                    HStack(spacing: 10) {
                        ItemIcon(icon: finding.icon, fallback: finding.categoryFallback, size: 26)
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 4) {
                                Text(finding.displayTitle).lineLimit(1)
                                if finding.needsAdmin { Label(L("password"), systemImage: "lock.fill").font(.fr(.caption2)).foregroundStyle(.secondary) }
                            }
                            if let command = finding.command, action == .command {
                                Text(command).font(.fr(.caption, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                            }
                            switch model.cleanResults[finding.id] {
                            case .skipped(let reason): Text(reason).font(.fr(.caption)).foregroundStyle(.secondary).lineLimit(2)
                            case .failed(let reason): Text(reason).font(.fr(.caption)).foregroundStyle(Theme.danger).lineLimit(2)
                            default: EmptyView()
                            }
                        }
                        Spacer()
                        Text(finding.reclaimable.formattedBytes).monospacedDigit()
                            .strikethrough(isCleaned(finding))
                            .foregroundStyle(isCleaned(finding) ? .secondary : .primary)
                        status(finding).frame(width: 20)
                    }
                    .padding(.vertical, 3)
                    .opacity(phase == .cleaning && model.cleanResults[finding.id] == nil ? 0.6 : 1)
                }
            }
        }
    }

    private func isCleaned(_ f: Finding) -> Bool {
        if case .cleaned = model.cleanResults[f.id] { return true }
        return false
    }

    @ViewBuilder
    private func status(_ finding: Finding) -> some View {
        switch model.cleanResults[finding.id] {
        case .cleaned: Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.safe).transition(.scale)
        case .skipped: Image(systemName: "minus.circle").foregroundStyle(.secondary)
        case .failed: Image(systemName: "xmark.octagon.fill").foregroundStyle(Theme.danger)
        case nil:
            if phase == .review {
                Button { withAnimation { items.removeAll { $0.id == finding.id } } } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless).foregroundStyle(.secondary).help(L("Remove from this clean"))
            } else {
                ProgressView().controlSize(.small)
            }
        }
    }

    // MARK: Done

    private var done: some View {
        let cleaned = items.filter(isCleaned)
        let skipped = items.filter { if case .skipped = model.cleanResults[$0.id] { return true }; return false }
        let failed = items.filter { if case .failed = model.cleanResults[$0.id] { return true }; return false }
        let trashed = cleaned.filter { $0.action == .trash }
        return VStack(spacing: 16) {
            Spacer(minLength: 10)
            ZStack {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
                    .scaleEffect(glints ? 1 : 0.7)
                ForEach(0..<3) { i in
                    Image(systemName: "sparkle")
                        .font(.system(size: [22, 14, 12][i], weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .offset(x: [56, -54, 44][i], y: [-40, -22, 42][i])
                        .scaleEffect(glints ? 1 : 0)
                        .animation(reduceMotion ? nil : .spring(duration: 0.5).delay(0.15 * Double(i)), value: glints)
                }
            }
            Text(L("You freed")).font(.fr(.title3)).foregroundStyle(.secondary)
            Text(Int64(shownFreed).formattedBytes)
                .font(.system(size: FontScale.size(52), weight: .bold, design: .rounded)).monospacedDigit()
                .contentTransition(.numericText(value: shownFreed))
                .accessibilityLabel(L("You freed") + " " + freed.formattedBytes)
            HStack(spacing: 6) {
                Image(systemName: "internaldrive")
                Text("\(freeBefore.formattedBytes) → ").monospacedDigit()
                Text(model.freeBytes.formattedBytes).monospacedDigit().foregroundStyle(Theme.safe).bold()
                Text(L("free"))
            }
            .foregroundStyle(.secondary)

            HStack(spacing: -6) {
                ForEach(Array(cleaned.prefix(10).enumerated()), id: \.element.id) { i, f in
                    ItemIcon(icon: f.icon, fallback: f.categoryFallback, size: 30)
                        .scaleEffect(glints ? 1 : 0.3).opacity(glints ? 1 : 0)
                        .animation(reduceMotion ? nil : .spring(duration: 0.4).delay(0.05 * Double(i)), value: glints)
                }
            }

            VStack(spacing: 6) {
                if !trashed.isEmpty {
                    NoteRow(symbol: "trash", text: String(format: L("%@ in the Trash · recoverable"), "\(trashed.count)"), button: L("Open Trash")) { model.openTrash() }
                }
                ForEach(skipped + failed) { f in
                    NoteRow(symbol: "minus.circle", text: String(format: L("%@ skipped"), f.displayTitle), button: nil) {}
                }
            }
            .padding(.horizontal, 30)
            Spacer()
            Button(L("Done")) { model.finishClean() }
                .buttonStyle(.borderedProminent).tint(Theme.accent).keyboardShortcut(.defaultAction)
                .padding(.bottom, 22)
        }
    }
}

private struct NoteRow: View {
    let symbol: String
    let text: String
    let button: String?
    let action: () -> Void
    var body: some View {
        HStack {
            Image(systemName: symbol).foregroundStyle(.secondary)
            Text(text).font(.fr(.callout))
            Spacer()
            if let button { Button(button, action: action) }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.quaternary.opacity(0.5)))
    }
}
