import SwiftUI
import WgplexKit

struct TunnelsView: View {
    @ObservedObject var state: WindowState

    var body: some View {
        let tunnels = state.model?.tunnels ?? []
        VStack(alignment: .leading, spacing: 0) {
            if let errors = state.status?.configErrors, !errors.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ошибки конфига").font(.headline)
                    ForEach(errors, id: \.self) { Text($0).textSelection(.enabled) }
                }
                .padding(10)
                Divider()
            }
            HStack(spacing: 0) {
                List(tunnels, id: \.row.name, selection: $state.selectedTunnel) { t in
                    TunnelListRow(detail: t) { state.toggle(t.row.name, on: $0) }
                }
                .frame(width: 240)
                Divider()
                if let t = tunnels.first(where: { $0.row.name == state.selectedTunnel }) {
                    TunnelDetailView(detail: t)
                } else {
                    Text(tunnels.isEmpty ? "Нет туннелей" : "Выберите туннель")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }
}

private struct TunnelListRow: View {
    let detail: TunnelDetail
    let toggle: (Bool) -> Void

    var body: some View {
        let row = detail.row
        HStack {
            Text(row.warn ? row.name + " ⚠" : row.name)
            Spacer()
            Toggle(
                "", isOn: Binding(get: { row.checked }, set: { toggle($0) })
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .disabled(!row.enabled)
        }
        .tag(row.name)
    }
}

private struct TunnelDetailView: View {
    let detail: TunnelDetail

    var body: some View {
        ScrollView {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    Text(detail.row.name).font(.title2).gridCellColumns(2)
                }
                if detail.row.startsOnResume {
                    GridRow { Text("запустится после возобновления").gridCellColumns(2) }
                }
                item("Endpoint", detail.endpoint)
                item("Интерфейс", detail.interface)
                item("Адреса", detail.addresses.isEmpty ? nil : detail.addresses.joined(separator: ", "))
                item("Handshake", detail.handshakeText)
                item("Трафик", detail.trafficText)
                item("Маршрутов", "\(detail.routeCount)")
                item("Проверка", detail.checkText)
                item("Ошибка", detail.error)
                item("Причина", detail.reason)
            }
            .textSelection(.enabled)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private func item(_ title: String, _ value: String?) -> some View {
        if let value {
            GridRow {
                Text(title).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                Text(value)
            }
        }
    }
}
