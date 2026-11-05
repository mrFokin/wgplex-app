import SwiftUI
import WgplexKit

/// Reads the new bytes of the engine log; runs off the main actor.
private enum LogFile {
    enum Failure: Sendable {
        case noAccess
        case notFound
        case other(String)
    }

    enum Result: Sendable {
        case failed(Failure)
        /// The file is shorter than the offset or is another file (rotation).
        case truncated
        /// Bytes starting at `start` of the file with inode `inode`.
        case data(start: UInt64, bytes: Data, inode: UInt64)
    }

    static func read(path: String, offset: UInt64, maxBytes: Int, inode: UInt64?) -> Result {
        let fd = open(path, O_RDONLY)
        if fd < 0 {
            switch errno {
            case EACCES: return .failed(.noAccess)
            case ENOENT: return .failed(.notFound)
            default: return .failed(.other(String(cString: strerror(errno))))
            }
        }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        var st = stat()
        guard fstat(fd, &st) == 0 else { return .failed(.other(String(cString: strerror(errno)))) }
        let ino = UInt64(st.st_ino)
        let size = UInt64(max(st.st_size, 0))
        if size < offset || (inode != nil && inode != ino) { return .truncated }
        // First read of a large file: only the last `maxBytes`.
        let start = offset == 0 && size > UInt64(maxBytes) ? size - UInt64(maxBytes) : offset
        do {
            try handle.seek(toOffset: start)
            let bytes = try handle.read(upToCount: 4 * 1024 * 1024) ?? Data()
            return .data(start: start, bytes: bytes, inode: ino)
        } catch {
            return .failed(.other(error.localizedDescription))
        }
    }
}

private enum Problem {
    case noPath
    case failure(LogFile.Failure)
}

struct LogsView: View {
    @ObservedObject var state: WindowState
    @State private var tail = LogTail()
    @State private var problem: Problem?
    /// Grows with every append; drives the auto-scroll (the line count stalls at `maxLines`).
    @State private var revision = 0
    @State private var inode: UInt64?
    @State private var level: LogLevel?
    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            if let status = state.status {
                if let problem {
                    Text(text(of: problem, status: status))
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

    private func text(of problem: Problem, status: Status) -> String {
        switch problem {
        case .noPath: return "Путь журнала неизвестен"
        case .failure(.noAccess): return "Журнал недоступен: нужно членство в группе \(status.controlGroup)"
        case .failure(.notFound): return "Файл журнала не найден: \(status.logPath)"
        case .failure(.other(let reason)): return "Не удалось прочитать журнал: \(reason)"
        }
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
            .onChange(of: revision) { _ in proxy.scrollTo("end") }
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
        problem = nil
        inode = nil
        guard let path, !path.isEmpty else {
            problem = .noPath
            return
        }
        while !Task.isCancelled {
            let offset = tail.offset
            let maxBytes = tail.maxBytes
            let known = inode
            let result = await Task.detached {
                LogFile.read(path: path, offset: offset, maxBytes: maxBytes, inode: known)
            }.value
            switch result {
            case .failed(let failure):
                problem = .failure(failure)
            case .truncated:
                problem = nil
                tail.reset()
                inode = nil
                revision += 1
                continue  // read the new file from its start at once
            case .data(let start, let bytes, let ino):
                problem = nil
                inode = ino
                if start != tail.offset { tail.offset = start }
                if !bytes.isEmpty {
                    tail.append(bytes)
                    revision += 1
                }
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }
}
