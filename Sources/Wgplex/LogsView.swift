import SwiftUI
import WgplexKit

/// Reads the new bytes of the engine log; runs off the main actor.
private enum LogFile {
    enum Result: Sendable {
        case unreadable
        /// The file is shorter than the offset.
        case truncated
        /// Bytes starting at `start`.
        case data(start: UInt64, bytes: Data)
    }

    static func read(path: String, offset: UInt64, maxBytes: Int) -> Result {
        guard let handle = FileHandle(forReadingAtPath: path) else { return .unreadable }
        defer { try? handle.close() }
        do {
            let size = try handle.seekToEnd()
            if size < offset { return .truncated }
            // First read of a large file: only the last `maxBytes`.
            let start = offset == 0 && size > UInt64(maxBytes) ? size - UInt64(maxBytes) : offset
            try handle.seek(toOffset: start)
            let bytes = try handle.read(upToCount: 4 * 1024 * 1024) ?? Data()
            return .data(start: start, bytes: bytes)
        } catch {
            return .unreadable
        }
    }
}

struct LogsView: View {
    @ObservedObject var state: WindowState
    @State private var tail = LogTail()
    @State private var unreadable = false
    @State private var level: LogLevel?
    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            if let status = state.status {
                if unreadable {
                    Text("Журнал недоступен: нужно членство в группе \(status.controlGroup)")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    controls
                    Divider()
                    list
                }
            } else {
                Text("Демон недоступен").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: state.status?.logPath) { await follow(path: state.status?.logPath) }
    }

    private var controls: some View {
        HStack {
            TextField("Поиск", text: $query).textFieldStyle(.roundedBorder)
            Picker("Уровень", selection: $level) {
                Text("Все").tag(LogLevel?.none)
                Text("Debug").tag(LogLevel?.some(.debug))
                Text("Info").tag(LogLevel?.some(.info))
                Text("Warn").tag(LogLevel?.some(.warn))
                Text("Error").tag(LogLevel?.some(.error))
            }
            .frame(width: 160)
        }
        .padding(8)
    }

    private var list: some View {
        let lines = tail.filtered(level: level, query: query)
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line.text)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(color(line.level))
                            .textSelection(.enabled)
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: lines.count) { _ in proxy.scrollTo("end") }
            .onAppear { proxy.scrollTo("end") }
        }
    }

    private func color(_ level: LogLevel) -> Color {
        switch level {
        case .error: return .red
        case .warn: return .orange
        default: return .primary
        }
    }

    /// Re-reads the file once a second until the section goes away.
    private func follow(path: String?) async {
        tail = LogTail()
        unreadable = false
        guard let path, !path.isEmpty else {
            unreadable = true
            return
        }
        while !Task.isCancelled {
            let offset = tail.offset
            let maxBytes = tail.maxBytes
            let result = await Task.detached {
                LogFile.read(path: path, offset: offset, maxBytes: maxBytes)
            }.value
            switch result {
            case .unreadable:
                unreadable = true
            case .truncated:
                unreadable = false
                tail.reset()
            case .data(let start, let bytes):
                unreadable = false
                if start != tail.offset { tail.offset = start }
                if !bytes.isEmpty { tail.append(bytes) }
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }
}
