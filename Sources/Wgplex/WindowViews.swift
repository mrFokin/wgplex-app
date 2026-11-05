import AppKit
import SwiftUI
import WgplexKit

/// Root of the window: sidebar, banner, action bar and the current section.
struct WindowRootView: View {
    @ObservedObject var state: WindowState

    var body: some View {
        NavigationSplitView {
            List(WindowSection.allCases, selection: sectionBinding) { section in
                Label(section.title, systemImage: section.symbol).tag(section)
            }
            .navigationSplitViewColumnWidth(min: 150, ideal: 170, max: 220)
        } detail: {
            VStack(spacing: 0) {
                BannerArea(state: state)
                ActionBarView(state: state)
                Divider()
                content
            }
        }
    }

    private var sectionBinding: Binding<WindowSection?> {
        Binding(get: { state.section }, set: { if let s = $0 { state.section = s } })
    }

    @ViewBuilder private var content: some View {
        switch state.section {
        case .tunnels: TunnelsView(state: state)
        case .rules: RulesView(state: state)
        case .diagnostics: DiagnosticsView(state: state)
        case .logs: LogsView(state: state)
        }
    }
}

/// Banner of `WindowModel` plus the last action message.
private struct BannerArea: View {
    @ObservedObject var state: WindowState

    var body: some View {
        VStack(spacing: 0) {
            if state.state == nil {
                line("Загрузка…", color: .secondary, target: nil)
            }
            if let banner = state.model?.banner {
                if let update = banner.update {
                    updateLine(banner.text, update)
                } else {
                    line(
                        banner.text, color: banner.kind == .paused ? .blue : .orange,
                        target: banner.target)
                }
            }
            if let m = state.message {
                line(m.text, color: m.isError ? .red : .green, target: nil)
            }
        }
    }

    /// Update banner: copy the upgrade command, open the release page.
    private func updateLine(_ text: String, _ update: UpdateInfo) -> some View {
        HStack {
            Text(text)
            Spacer()
            Button("Скопировать команду") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(update.command, forType: .string)
            }
            if let url = URL(string: update.url) {
                Link("Страница релиза", destination: url)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.18))
    }

    private func line(_ text: String, color: Color, target: ProblemTarget?) -> some View {
        HStack {
            Text(text)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(color.opacity(0.18))
        .contentShape(Rectangle())
        .onTapGesture {
            if let target { state.navigate(to: target) }
        }
    }
}

/// Pause, disable all, reload and the config folder, in every section.
private struct ActionBarView: View {
    @ObservedObject var state: WindowState

    var body: some View {
        let bar = state.model?.actions
        HStack {
            Button(bar?.pauseTitle ?? "Приостановить") { state.togglePause() }
                .disabled(!(bar?.pauseEnabled ?? false) || state.busy)
            Button("Выключить все") { state.disableAll() }
                .disabled(!(bar?.disableAllEnabled ?? false) || state.busy)
            Button("Перечитать конфиг") { state.reload() }
                .disabled(!(bar?.reloadEnabled ?? false) || state.busy)
            Spacer()
            if let status = state.status { ConfigDirView(path: status.configDir) }
        }
        .padding(8)
    }
}

/// "Открыть папку конфига" or the path with the admin note.
private struct ConfigDirView: View {
    let path: String

    var body: some View {
        let access = ConfigDirAccess.describe(
            path: path, canRead: FileManager.default.isReadableFile(atPath: path))
        switch access {
        case .open(let p):
            Button("Открыть папку конфига") {
                NSWorkspace.shared.open(URL(fileURLWithPath: p, isDirectory: true))
            }
        case .adminOnly(let p):
            VStack(alignment: .trailing) {
                Text(access.note ?? "")
                Text(p).foregroundStyle(.secondary).textSelection(.enabled)
            }
            .font(.caption)
        }
    }
}

/// Wrapper that gives table rows an identity.
struct Indexed<T>: Identifiable {
    let id: Int
    let value: T
}
