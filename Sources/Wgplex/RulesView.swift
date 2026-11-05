import SwiftUI
import WgplexKit

struct RulesView: View {
    @ObservedObject var state: WindowState

    var body: some View {
        let rows = (state.model?.rules ?? []).map { Indexed(id: $0.index, value: $0) }
        if rows.isEmpty {
            Text("Нет правил").foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(rows, selection: $state.selectedRule) {
                TableColumn("№") { Text("\($0.value.index)") }.width(30)
                TableColumn("Сервисы") { Text($0.value.services.joined(separator: ", ")) }
                TableColumn("Через") { Text($0.value.via.joined(separator: ", ")) }
                TableColumn("Туннель") { Text($0.value.tunnel ?? "—") }
                TableColumn("Состояние") { row in
                    let r = row.value
                    Text(r.reasonText.map { "\(r.stateText) (\($0))" } ?? r.stateText)
                        .foregroundStyle(r.isProblem ? Color.orange : Color.primary)
                }
            }
        }
    }
}
