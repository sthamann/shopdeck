import SwiftUI
import ShopdeckCore

struct ListConfigurationView: View {
    var model: AppModel
    let entity: String
    @Environment(\.dismiss) private var dismiss
    @LocalState<ListConfiguration> private var configuration: ListConfiguration
    @LocalState<String> private var field = ""
    @LocalState<String> private var customTitle = ""
    @LocalState<String> private var filterName = ""
    @LocalState<String> private var filterField = "stock"
    @LocalState<String> private var operation = "lte"
    @LocalState<String> private var value = "5"
    @LocalState<String?> private var error: String?
    init(model: AppModel, entity: String) { self.model = model; self.entity = entity; _configuration = LocalState(initialValue: model.listConfiguration) }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(T("Deine Liste. Deine Arbeitsweise.")).font(.title2.bold())
            TabView {
                VStack(alignment: .leading, spacing: 14) {
                    if entity=="product"{Toggle(T("Produktvorschaubilder anzeigen"),isOn:Binding(get:{configuration.showProductThumbnails != false},set:{configuration.showProductThumbnails=$0}))}
                    Text(T("Ziehe die Spaltenköpfe in der Liste an die gewünschte Position. Hier kannst du Felder hinzufügen und entfernen.")).font(.callout).foregroundStyle(.secondary)
                    List { ForEach(Array(configuration.columns.enumerated()), id: \.element.id) { index, column in
                        HStack { Image(systemName: "line.3.horizontal").foregroundStyle(.secondary); Text(T(column.title)); Spacer(); Button { move(index, -1) } label: { Image(systemName: "arrow.up") }.disabled(index == 0); Button { move(index, 1) } label: { Image(systemName: "arrow.down") }.disabled(index == configuration.columns.count - 1); Button { configuration.columns.remove(at: index) } label: { Image(systemName: "minus.circle") }.disabled(configuration.columns.count == 1) }.buttonStyle(.borderless)
                    } }
                    Picker(T("Feld hinzufügen"), selection: $field) { Text(T("Feld auswählen")).tag(""); ForEach(ListConfiguration.fields(entity).filter { candidate in !configuration.columns.contains(where: { $0.field == candidate.field }) }) { column in Text(T(column.title)).tag(column.field) } }
                    HStack { TextField(T("Oder eigener Feldpfad"), text: $field); TextField(T("Spaltenname"), text: $customTitle); Button(T("Hinzufügen")) { let known = ListConfiguration.fields(entity).first { $0.field == field }; configuration.columns.append(.init(field, customTitle.isEmpty ? known?.title ?? field : customTitle)); field = ""; customTitle = "" }.disabled(field.isEmpty || configuration.columns.contains { $0.field == field }) }
                    Text(T("Eigene Felder sind über ihren API Pfad erreichbar, zum Beispiel customFields.mein_feld. Leere Werte erscheinen als –.")).font(.caption).foregroundStyle(.secondary)
                }.padding(18).tabItem { Text(T("Spalten")) }
                VStack(alignment: .leading, spacing: 15) {
                    Text(T("Lege Schnellfilter an. Mehrere eingeschaltete Filter gelten gemeinsam für die gesamte Suche, auch über mehrere Seiten.")).font(.callout).foregroundStyle(.secondary)
                    List { ForEach(configuration.filters) { filter in HStack { VStack(alignment: .leading, spacing: 4) { Text(filter.name); Text("\(filter.field) \(filter.operation) \(filter.value)").font(.caption).foregroundStyle(.secondary) }; Spacer(); Button { configuration.filters.removeAll { $0.id == filter.id } } label: { Image(systemName: "trash") }.buttonStyle(.borderless) } } }
                    TextField(T("Filtername"), text: $filterName)
                    Picker(T("Feld"), selection: $filterField) { ForEach(ListConfiguration.fields(entity).filter { $0.field != "shop" && !$0.field.contains(".0.") }) { column in Text(T(column.title)).tag(column.field) } }
                    TextField(T("Feldpfad"), text: $filterField)
                    HStack { Picker(T("Vergleich"), selection: $operation) { Text("=").tag("equals"); Text(T("Enthält")).tag("contains"); Text("≤").tag("lte"); Text("≥").tag("gte"); Text("<").tag("lt"); Text(">").tag("gt") }; TextField(T("Wert"), text: $value) }
                    HStack { Text(T("Für Ja oder Nein true oder false eingeben. Datumswerte im ISO Format verwenden.")).font(.caption).foregroundStyle(.secondary); Spacer(); Button(T("Filter hinzufügen")) { let filter = RecordFilter(name: filterName, field: filterField, operation: operation, value: value); do { _ = try filter.criteria(); configuration.filters.append(filter); filterName = "" } catch { self.error = error.localizedDescription } }.disabled(filterName.trimmingCharacters(in: .whitespaces).isEmpty || value.isEmpty) }
                }.padding(18).tabItem { Text(T("Schnellfilter")) }
            }
            if let error { Text(error).font(.caption).foregroundStyle(.orange) }
            HStack { Button(T("Abbrechen")) { dismiss() }; Button(T("Standardspalten")) { configuration.columns = ListConfiguration.standard(entity).columns }; Spacer(); Button(T("Speichern")) { model.saveListConfiguration(configuration, entity: entity); model.activeFilters.removeAll { active in !configuration.filters.contains { $0.id == active.id } }; dismiss() }.buttonStyle(.borderedProminent) }
        }.padding(26).frame(width: 720, height: 650).onAppear { filterField = entity == "product" ? "stock" : entity == "order" ? "amountTotal" : "orderCount" }
    }
    private func move(_ index: Int, _ offset: Int) { configuration.columns.swapAt(index, index + offset) }
}
