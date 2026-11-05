import SwiftUI
import WgplexKit

struct DiagnosticsView: View {
    @ObservedObject var state: WindowState
    @State private var query = ""
    @State private var explainText: String?
    @State private var explainFailed = false
    @State private var routes: Routes?
    @State private var routesError: String?
    @State private var loading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Домен или IP-адрес", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(explain)
                Button("Объяснить", action: explain)
                    .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || loading)
            }
            if let explainText {
                Text(explainText)
                    .foregroundStyle(explainFailed ? Color.red : Color.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                Text("Маршруты").font(.headline)
                Spacer()
                Button("Обновить", action: loadRoutes).disabled(loading)
            }
            if let routesError { Text(routesError).foregroundStyle(.red) }
            if let routes {
                if let sync = routes.syncError { Text("Ошибка синхронизации: \(sync)").foregroundStyle(.orange) }
                Table(routes.routes.enumerated().map { Indexed(id: $0.offset, value: $0.element) }) {
                    TableColumn("Префикс") { Text($0.value.prefix) }
                    TableColumn("Цель") { Text(Self.targetText($0.value.target)) }
                    TableColumn("Туннель") { Text($0.value.tunnel ?? "—") }
                    TableColumn("Источник") { Text(Self.sourceText($0.value.source)) }
                    TableColumn("Имена") { Text($0.value.names.joined(separator: ", ")) }
                }
            } else {
                Spacer()
            }
        }
        .padding(12)
    }

    private func explain() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, !loading else { return }
        loading = true
        Task {
            let (result, failure) = await state.poller.perform { try await $0.explain(q) }
            explainFailed = failure != nil
            explainText = failure ?? result.map(Self.describe)
            loading = false
        }
    }

    private func loadRoutes() {
        guard !loading else { return }
        loading = true
        Task {
            let (result, failure) = await state.poller.perform { try await $0.routes() }
            routesError = failure
            if let result { routes = result }
            loading = false
        }
    }

    static func targetText(_ t: RouteTarget) -> String {
        switch t {
        case .tunnel: return "туннель"
        case .direct: return "напрямую"
        case .reject: return "блокировка"
        case .unknown(let s): return s
        }
    }

    static func sourceText(_ s: RouteSource) -> String {
        switch s {
        case .endpoint: return "endpoint"
        case .allowedIPs: return "allowed-ips"
        case .ruleCIDR: return "rule-cidr"
        case .dynamic: return "dynamic"
        case .unknown(let s): return s
        }
    }

    /// Plain-text view of an `Explanation`; only the fields that are set.
    static func describe(_ e: Explanation) -> String {
        var lines = [e.query]
        if let r = e.rule {
            lines.append("Правило \(r.index): \(r.services.joined(separator: ", "))")
            if !r.via.isEmpty { lines.append("Через: \(r.via.joined(separator: ", "))") }
            if let t = r.tunnel { lines.append("Туннель: \(t)") }
            if r.inFallback { lines.append("Без туннеля (fallback)") } else if r.degraded {
                lines.append("На резерве")
            }
        } else {
            lines.append("Правило не найдено")
        }
        if let s = e.skipped { lines.append("Пропущено правило \(s.index)") }
        if let u = e.upstream { lines.append("Upstream: \(u)") }
        if let z = e.zone { lines.append("Зона: \(z)") }
        if !e.servers.isEmpty { lines.append("DNS-серверы: \(e.servers.joined(separator: ", "))") }
        if e.dropAAAA { lines.append("AAAA отбрасываются") }
        if !e.addrs.isEmpty { lines.append("Адреса: \(e.addrs.joined(separator: ", "))") }
        if let r = e.route {
            var s = "Маршрут: \(r.prefix) → \(targetText(r.target))"
            if let t = r.tunnel { s += " (\(t))" }
            lines.append(s)
            if let sk = r.skipped { lines.append("Пропущен: \(sk)") }
        }
        return lines.joined(separator: "\n")
    }
}
