import FreeroomCore
import SwiftUI

enum SidebarItem: Hashable {
    case everything
    case ecosystem(String)
    case source(FindingSource)
    case settings
    case history
}

struct MainView: View {
    @Environment(AppModel.self) private var model
    @State private var sidebar: SidebarItem = .everything
    @State private var search = ""
    @State private var groupByEcosystem = true
    @State private var showInspector = true
    @State private var columns: NavigationSplitViewVisibility = .all

    private var visible: [Finding] {
        model.findings.filter { f in
            let inSidebar: Bool = switch sidebar {
            case .everything, .settings, .history: true
            case .ecosystem(let id): f.ecosystem.id == id
            case .source(let s): f.source == s
            }
            return inSidebar && (search.isEmpty || f.title.localizedCaseInsensitiveContains(search) || f.displayTitle.localizedCaseInsensitiveContains(search)
                                 || f.paths.contains { $0.localizedCaseInsensitiveContains(search) })
        }
    }

    var body: some View {
        if !model.onboarded {
            VStack(spacing: 0) {
                BrandTitle().padding(.top, 18)
                OnboardingView()
            }
        } else {
            splitView
        }
    }

    private var sidebarSelection: Binding<SidebarItem> {
        Binding(
            get: { model.route == .settings ? .settings : model.route == .history ? .history : sidebar },
            set: { item in
                switch item {
                case .settings: model.route = .settings
                case .history: model.route = .history
                default: model.route = .findings; sidebar = item
                }
            })
    }

    private var splitView: some View {
        @Bindable var model = model
        return NavigationSplitView(columnVisibility: $columns) {
            sidebarList
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 300)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            Group {
                if model.route == .settings {
                    SettingsView()
                } else if model.route == .history {
                    HistoryView()
                } else {
                    ZStack(alignment: .bottom) {
                        if model.simpleMode { SimpleView() } else { content }
                        SelectionBar().padding(.bottom, 14)
                    }
                }
            }
            .inspector(isPresented: Binding(get: { showInspector && !model.simpleMode && model.route == .findings },
                                            set: { showInspector = $0 })) {
                Group {
                    if let id = model.inspected, let finding = model.finding(id: id) {
                        FindingInspector(finding: finding)
                    } else {
                        ContentUnavailableView(L("Select an item"), systemImage: "sidebar.right",
                                               description: Text(L("Details, evidence and paths appear here.")))
                    }
                }
                .inspectorColumnWidth(min: 280, ideal: 310, max: 380)
            }
        }
        .onChange(of: columns) { _, value in if value != .all { columns = .all } }
        .searchable(text: $search, placement: .toolbar, prompt: L("Search"))
        .toolbar { toolbar }
        .sheet(isPresented: Binding(get: { model.pendingClean != nil },
                                    set: { if !$0 { model.finishClean() } })) {
            CleanSheet(items: model.pendingClean ?? []).environment(model)
        }
        .navigationTitle(model.route == .settings ? L("Settings") : model.route == .history ? L("History") : title)
        .navigationSubtitle(String(format: L("%@ free of %@"), model.freeBytes.formattedBytes, model.totalBytes.formattedBytes))
        .onKeyPress(.space) {
            guard let id = model.inspected, let f = model.finding(id: id), f.isCleanable else { return .ignored }
            if model.selection.contains(id) { model.selection.remove(id) } else { model.selection.insert(id) }
            return .handled
        }
        .background(KeyboardShortcuts())
    }

    private var title: String {
        switch sidebar {
        case .everything: L("Everything")
        case .ecosystem(let id): model.ecosystems.first { $0.0.id == id }.map { L($0.0.title) } ?? "Freeroom"
        case .source(.agent): L("Found by Claude Code")
        case .source(.rule): L("Found by rules")
        case .settings: L("Settings")
        case .history: L("History")
        }
    }

    // MARK: Sidebar

    private var sidebarList: some View {
        List(selection: sidebarSelection) {
            Label { HStack { Text(L("Everything")); Spacer(); Text(model.cleanableTotal.formattedBytes).monospacedDigit().foregroundStyle(.secondary) } }
                icon: { Image(systemName: "square.grid.2x2") }
                .tag(SidebarItem.everything)

            Section(L("Ecosystems")) {
                ForEach(model.ecosystems, id: \.0) { eco, bytes in
                    HStack(spacing: 8) {
                        ItemIcon(icon: eco.icon, fallback: "folder", size: 20)
                        Text(L(eco.title)).lineLimit(1)
                        Spacer()
                        Text(bytes.formattedBytes).monospacedDigit().foregroundStyle(.secondary).font(.callout)
                    }
                    .tag(SidebarItem.ecosystem(eco.id))
                }
            }
            Section(L("Found by")) {
                Label(L("Rules"), systemImage: "ruler").badge(model.findings.filter { $0.source == .rule }.count)
                    .tag(SidebarItem.source(.rule))
                Label { Text("Claude Code") } icon: { AgentMark(size: 14) }
                    .badge(model.findings.filter { $0.source == .agent }.count)
                    .tag(SidebarItem.source(.agent))
            }
            Section {
                Label { HStack { Text(L("History")); Spacer(); Text(model.freedAllTime.formattedBytes).monospacedDigit().foregroundStyle(.secondary) } }
                    icon: { Image(systemName: "clock.arrow.circlepath") }
                    .tag(SidebarItem.history)
            }
        }
        .safeAreaInset(edge: .top) {
            BrandTitle().padding(.horizontal, 14).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                if model.freedAllTime > 0 {
                    Label(String(format: L("%@ freed so far"), model.freedAllTime.formattedBytes), systemImage: "clock.arrow.circlepath")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button { model.route = model.route == .settings ? .findings : .settings } label: {
                    Label(L("Settings"), systemImage: "gearshape")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6).padding(.horizontal, 8)
                        .background(model.route == .settings ? Theme.accent.opacity(0.15) : .clear,
                                    in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
            .padding(10)
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if model.findings.isEmpty {
            EmptyStateView()
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if model.agentScanLive { AgentLiveBanner() }
                    hero
                    if model.showDiskMap && sidebar == .everything && search.isEmpty {
                        TreemapView(findings: visible.filter(\.isCleanable))
                            .frame(height: 230)
                    }
                    list
                }
                .padding(20)
                .padding(.bottom, 70)
            }
        }
    }

    private var hero: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L("You can free up to")).foregroundStyle(.secondary)
                Text(model.cleanableTotal.formattedBytes)
                    .font(.system(size: 40, weight: .semibold, design: .rounded)).monospacedDigit()
                    .contentTransition(.numericText(value: Double(model.cleanableTotal)))
                HStack(spacing: 6) {
                    SafetyBadge(safety: .safe, value: model.total(.safe))
                    SafetyBadge(safety: .review, value: model.total(.review))
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Spacer(minLength: 18)
                DiskBar(total: model.totalBytes, free: model.freeBytes, safe: model.total(.safe),
                        review: model.total(.review), keep: model.findings.filter { $0.safety == .keep }.reduce(0) { $0 + $1.sizeBytes })
                HStack(spacing: 12) {
                    LegendDot(symbol: Theme.icon(.safe), color: Theme.safe, label: L("Safe"), value: model.total(.safe))
                    LegendDot(symbol: Theme.icon(.review), color: Theme.review, label: L("Review"), value: model.total(.review))
                    LegendDot(symbol: "circle", color: .secondary, label: L("Free"), value: model.freeBytes)
                }
            }
        }
    }

    private var list: some View {
        let maxSize = Double(visible.first?.sizeBytes ?? 1)
        let groups: [(String, Ecosystem?, [Finding])] = groupByEcosystem
            ? Dictionary(grouping: visible, by: \.ecosystem)
                .map { (L($0.key.title), Optional($0.key), $0.value) }
                .sorted { $0.2.reduce(0) { $0 + $1.sizeBytes } > $1.2.reduce(0) { $0 + $1.sizeBytes } }
            : [(L("By size"), nil, visible)]
        return VStack(alignment: .leading, spacing: 16) {
            ForEach(groups, id: \.0) { title, eco, items in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        if let eco { ItemIcon(icon: eco.icon, size: 20) }
                        Text(title).font(.headline)
                        let cleanable = items.filter { $0.isCleanable && $0.safety == .safe }
                        if !cleanable.isEmpty {
                            Button(L("Select all")) { model.selection.formUnion(cleanable.map(\.id)) }
                                .buttonStyle(.link).font(.callout)
                        }
                        Spacer()
                        Text(items.reduce(Int64(0)) { $0 + $1.reclaimable }.formattedBytes)
                            .monospacedDigit().foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 4)
                    VStack(spacing: 0) {
                        ForEach(items) { finding in
                            FindingRow(finding: finding, fraction: Double(finding.sizeBytes) / maxSize)
                            if finding.id != items.last?.id { Divider().padding(.leading, 76) }
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Picker(L("Mode"), selection: Binding(get: { model.simpleMode }, set: { model.simpleMode = $0; model.route = .findings })) {
                Label(L("Simple"), systemImage: "square.grid.2x2.fill").tag(true)
                Label(L("Detailed"), systemImage: "list.bullet.rectangle").tag(false)
            }
            .pickerStyle(.segmented)
            .labelStyle(.titleAndIcon)
            .help(L("Simple: big icons and one button. Detailed: disk map, list and inspector."))
        }
        ToolbarItem {
            Picker(L("Group"), selection: $groupByEcosystem) {
                Label(L("Ecosystem"), systemImage: "square.grid.2x2").tag(true)
                Label(L("Size"), systemImage: "list.number").tag(false)
            }
            .pickerStyle(.segmented)
            .help(L("Group by ecosystem or list by size"))
        }
        ToolbarItem {
            Button { model.runRules() } label: {
                Label(L("Check now"), systemImage: "arrow.clockwise")
                    .symbolEffect(.rotate, isActive: model.isRunningRules)
            }
            .help(L("Check now: rules only, no AI") + " (⌘R)")
            .keyboardShortcut("r")
        }
        ToolbarItem {
            Button { model.copyScanCommand() } label: { Label(L("Deep scan"), systemImage: "terminal") }
                .help(String(format: L("Copy %@ for Claude Code"), "/freeroom:scan"))
        }
        ToolbarItem {
            Button { showInspector.toggle() } label: { Label(L("Inspector"), systemImage: "sidebar.right") }
                .keyboardShortcut("i", modifiers: [.command, .option])
                .disabled(model.simpleMode)
        }
        ToolbarItem {
            Button { model.route = model.route == .settings ? .findings : .settings } label: {
                Label(L("Settings"), systemImage: "gearshape")
            }
            .help(L("Settings") + " (⌘,)")
        }
    }
}

/// Global shortcuts: ⌘A selects all Safe, ⌘⏎ reviews the selection.
private struct KeyboardShortcuts: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        ZStack {
            Button("") { model.selection = Set(model.safeFindings.map(\.id)) }.keyboardShortcut("a")
            Button("") { model.requestClean(model.selectedFindings) }.keyboardShortcut(.return, modifiers: .command)
        }
        .opacity(0).allowsHitTesting(false)
    }
}

/// Floating glass capsule with the selection and the main action.
struct SelectionBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 12) {
            if model.selection.isEmpty {
                Image(systemName: "keyboard").foregroundStyle(.secondary)
                Text(L("space selects · ⌘A all Safe · ⌘⏎ clean")).foregroundStyle(.secondary).font(.callout)
            } else {
                HStack(spacing: -8) {
                    ForEach(model.selectedFindings.prefix(5)) { f in
                        ItemIcon(icon: f.icon, fallback: f.categoryFallback, size: 24)
                            .background(Circle().fill(.background).padding(-2))
                    }
                }
                Text("**\(model.selectedBytes.formattedBytes)** · \(String(format: L("%@ items"), "\(model.selection.count)"))")
                    .monospacedDigit()
                Text("→ " + String(format: L("%@ free"), (model.freeBytes + model.selectedBytes).formattedBytes))
                    .foregroundStyle(.secondary).monospacedDigit()
                Button { model.selection = [] } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless).foregroundStyle(.secondary).help(L("Clear selection"))
            }
            Button(L("Review & clean")) { model.requestClean(model.selectedFindings) }
                .buttonStyle(.borderedProminent).tint(Theme.accent)
                .disabled(model.selection.isEmpty)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .freeroomGlass(cornerRadius: 22)
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .animation(.snappy, value: model.selection)
    }
}

struct AgentLiveBanner: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        HStack(spacing: 10) {
            AgentMark(size: 18).symbolEffect(.pulse)
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Claude Code is scanning…")).font(.callout.weight(.semibold))
                let agent = model.findings.filter { $0.source == .agent }
                Text(agent.first.map { String(format: L("%@ findings · latest: %@ %@"), "\(agent.count)", $0.displayTitle, $0.sizeBytes.formattedBytes) } ?? L("Waiting for the first finding"))
                    .font(.caption)
            }
            Spacer()
            ProgressView().controlSize(.small)
        }
        .foregroundStyle(Theme.agent)
        .padding(12)
        .background(Theme.agentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct EmptyStateView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        VStack(spacing: 14) {
            if model.isRunningRules {
                ProgressView().controlSize(.large)
                Text(String(format: L("Measuring %@ known locations…"), "\(Catalog.locations.count)")).foregroundStyle(.secondary)
            } else {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
                Text(L("Nothing worth cleaning")).font(.title2.weight(.semibold))
                Text(String(format: L("%@ free"), model.freeBytes.formattedBytes)).foregroundStyle(.secondary).monospacedDigit()
                HStack {
                    Button(L("Check now")) { model.runRules() }.buttonStyle(.borderedProminent).tint(Theme.accent)
                    Button(L("Deep scan with Claude Code")) { model.copyScanCommand() }
                }
                HStack(spacing: -6) {
                    ForEach(Array(Catalog.locations.filter { $0.icon?.app != nil || $0.icon?.brand != nil }
                        .sorted { ($0.popularity ?? 0) > ($1.popularity ?? 0) }.prefix(12).enumerated()), id: \.offset) { _, loc in
                        ItemIcon(icon: loc.icon, size: 26)
                    }
                }
                .padding(.top, 10)
                Text(String(format: L("Watching %@ known locations"), "\(Catalog.locations.count)")).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
