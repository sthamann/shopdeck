import SwiftUI
import ShopdeckCore

struct RecordDetailView: View {
    var model: AppModel
    let record: ShopRecord
    @Environment(\.dismiss) private var dismiss
    @LocalState<JSONValue> private var data: JSONValue = .null
    @LocalState<String> private var name = ""
    @LocalState<String> private var stock = ""
    @LocalState<Bool> private var active = true
    @LocalState<String> private var description = ""
    @LocalState<Bool> private var busy = false
    @LocalState<Bool> private var loading = true
    @LocalState<String?> private var message: String?
    @LocalState<Bool> private var confirm = false
    @LocalState<Bool> private var documents = false
    @LocalState<String> private var fieldSearch = ""
    private var entity: String { record.entity }
    private var currency: String? { data["currency"]["isoCode"].string }
    private var changes: [String: JSONValue] {
        var result: [String: JSONValue] = [:]
        if name != (data.at("name").string ?? "") { result["name"] = .string(name) }
        if stock != String(Int(data["stock"].number ?? 0)), let number = Double(stock) { result["stock"] = .number(number) }
        if active != (data["active"].bool ?? true) { result["active"] = .bool(active) }
        if description != (data.at("description").string ?? "") { result["description"] = .string(description) }
        return result
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                ShopIcon(shop: record.shop, size: 40)
                VStack(alignment: .leading, spacing: 5) { Text(entity == "product" ? T("Produktdetails") : entity == "order" ? T("Bestelldetails") : T("Kundendetails")).font(.title2.bold()); Text(record.shop.name + (record.shop.isDemo ? " · " + T("Demodaten") : "")).font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button { model.toggleBookmark(ShopRecord(shop: record.shop, data: data, entity: entity)) } label: { Image(systemName: model.isBookmarked(record) ? "star.fill" : "star") }.disabled(loading || data == .null).help(T(model.isBookmarked(record) ? "Lesezeichen entfernen" : "Lesezeichen setzen"))
                if entity == "order" { Button { documents = true } label: { Label(T("Dokumente"), systemImage: "doc.richtext") } }
                Button { copyText(record.data["id"].string ?? ""); model.notice = T("ID kopiert") } label: { Image(systemName: "doc.on.doc") }.help(T("ID kopieren"))
                Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }.disabled(loading || busy).help(T("Aktualisieren"))
            }.padding(24)
            Divider()
            if loading { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            else if data == .null { ContentUnavailableView(T("Daten konnten nicht geladen werden"), systemImage: "exclamationmark.triangle", description: Text(message ?? "")); Button(T("Erneut laden")) { Task { await load() } }.padding(24) }
            else {
                TabView {
                    ScrollView { VStack(alignment: .leading, spacing: 20) { overview }.padding(26).frame(maxWidth: .infinity, alignment: .leading) }.tabItem { Text(T("Übersicht")) }
                    if let item = model.followUpDraft(ShopRecord(shop: record.shop, data: data, entity: entity)) {
                        FollowUpEditor(model: model, item: item).padding(26).tabItem { Label(T("Notizen und Wiedervorlage"), systemImage: "bookmark") }
                    }
                    if entity == "product" {
                        Form {
                            Section {TextField(T("Bestand"),text:$stock);Toggle(T("Aktiv"),isOn:$active)}
                            Section {Text(T("Preise, Varianten, Medien und alle weiteren Produktfelder bearbeitest du in der vollständigen Shopware Maske.")).font(.callout).foregroundStyle(.secondary);if !record.shop.isDemo{Button(T("Vollständig in Shopware bearbeiten")){model.openAdministration(record);dismiss()}.buttonStyle(.borderedProminent)}}
                        }.formStyle(.grouped).tabItem { Text(T("Bestand und Status")) }
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        HStack { TextField(T("Feld oder Inhalt suchen"), text: $fieldSearch).textFieldStyle(.roundedBorder); Button(T("JSON kopieren")) { copyText(data.pretty) } }
                        Text(T("Alle vom Shop gelieferten Felder einschließlich Zusatzfeldern und geladenen Verknüpfungen. Aufklappen zeigt auch verschachtelte Werte.")).font(.caption).foregroundStyle(.secondary)
                        ScrollView { VStack(alignment: .leading, spacing: 10) { ForEach((data.object ?? [:]).keys.sorted().filter { fieldSearch.isEmpty || $0.localizedCaseInsensitiveContains(fieldSearch) || data[$0].pretty.localizedCaseInsensitiveContains(fieldSearch) }, id: \.self) { key in JSONFieldView(name: key, value: data[key]) } }.frame(maxWidth: .infinity, alignment: .leading) }
                    }.padding(24).tabItem { Text(T("Alle Felder")) }
                }.padding(.top, 12)
            }
            if let message, data != .null { Text(message).font(.caption).foregroundStyle(.orange).padding(20) }
            Divider()
            HStack {
                if !record.shop.isDemo { Button(entity=="product" ? T("Vollständig in Shopware bearbeiten"):T("In Administration öffnen")) { model.openAdministration(record); dismiss() } }
                Spacer(); Button(T("Schließen")) { dismiss() }.keyboardShortcut(.cancelAction)
                if entity == "product" { Button(T("Änderungen speichern")) { confirm = true }.buttonStyle(.borderedProminent).disabled(busy || loading || data == .null || changes.isEmpty || Int(stock) == nil || (Int(stock) ?? -1) < 0) }
            }.padding(20)
        }.frame(width: 820, height: 740).task { await load() }
        .sheet(isPresented: $documents) { OrderDocumentsView(model: model, orders: [record]) }
        .confirmationDialog(T("Änderungen übernehmen?"), isPresented: $confirm) { Button(T("Jetzt speichern")) { Task { busy = true; defer { busy = false }; do { _ = try Validation.productChanges(changes); try await model.saveProduct(record, changes: changes); dismiss() } catch { message = error.localizedDescription } } } } message: { Text(changes.keys.sorted().map { T($0) }.joined(separator: ", ") + " · " + record.shop.name) }
    }
    @ViewBuilder private var overview: some View {
        if entity == "order" {
            Text("#" + data["orderNumber"].localizedDisplayString).font(.system(size: 30, weight: .bold))
            field(T("Datum"), dateLabel(data["orderDateTime"])); field(T("Status"), T(data["stateMachineState"]["technicalName"].localizedDisplayString))
            field(T("Gesamt"), amount(data["amountTotal"])); field(T("Nettobetrag"), amount(data["amountNet"])); field(T("Versandkosten"), amount(data["shippingTotal"]))
            field(T("Kunde"), [data["orderCustomer"]["firstName"].string, data["orderCustomer"]["lastName"].string].compactMap { $0 }.joined(separator: " ")); field(T("E Mail"), data["orderCustomer"]["email"].localizedDisplayString)
            Divider(); Text(T("Positionen")).font(.headline)
            ForEach(Array(data["lineItems"].array.enumerated()), id: \.offset) { _, item in HStack(alignment: .top) { VStack(alignment: .leading, spacing: 5) { Text(item["label"].localizedDisplayString).fontWeight(.medium); Text(T("Anzahl") + ": " + item["quantity"].localizedDisplayString + " · " + item["payload"]["productNumber"].localizedDisplayString).font(.caption).foregroundStyle(.secondary) }; Spacer(); Text(amount(item["totalPrice"])) }; Divider() }
            address(T("Rechnungsadresse"), data["billingAddress"])
            ForEach(Array(data["deliveries"].array.enumerated()), id: \.offset) { _, delivery in Divider(); Text(T("Lieferung")).font(.headline); field(T("Versandart"), delivery["shippingMethod"]["name"].localizedDisplayString); field(T("Status"), T(delivery["stateMachineState"]["technicalName"].localizedDisplayString)); address(T("Lieferadresse"), delivery["shippingOrderAddress"]) }
            ForEach(Array(data["transactions"].array.enumerated()), id: \.offset) { _, transaction in Divider(); Text(T("Zahlung")).font(.headline); field(T("Zahlungsart"), transaction["paymentMethod"]["name"].localizedDisplayString); field(T("Status"), T(transaction["stateMachineState"]["technicalName"].localizedDisplayString)) }
        } else if entity == "customer" {
            Text([data["firstName"].string, data["lastName"].string].compactMap { $0 }.joined(separator: " ")).font(.system(size: 28, weight: .bold))
            ForEach(["customerNumber", "email", "company", "active", "guest", "orderCount", "orderTotalAmount", "group.name", "salesChannel.name"], id: \.self) { path in field(label(path), data.at(path).bool.map { $0 ? T("Ja") : T("Nein") } ?? data.at(path).localizedDisplayString) }
            Divider(); address(T("Rechnungsadresse"), data["defaultBillingAddress"]); address(T("Lieferadresse"), data["defaultShippingAddress"])
            if !data["addresses"].array.isEmpty { Divider(); Text(T("Adressbuch")).font(.headline); ForEach(Array(data["addresses"].array.enumerated()), id: \.offset) { index, entry in address("\(index + 1)", entry) } }
        } else {
            Text(data.at("name").localizedDisplayString).font(.system(size: 28, weight: .bold))
            ForEach(["productNumber", "active", "stock", "availableStock", "manufacturer.name", "ean", "manufacturerNumber", "weight", "tax.taxRate"], id: \.self) { path in field(label(path), data.at(path).bool.map { $0 ? T("Ja") : T("Nein") } ?? data.at(path).localizedDisplayString) }
            if !data["price"].array.isEmpty { Divider(); Text(T("Preise je Währung")).font(.headline); ForEach(Array(data["price"].array.enumerated()), id: \.offset) { _, price in VStack(alignment: .leading, spacing: 8) { field(T("Währungs ID"), price["currencyId"].localizedDisplayString); field(T("Bruttopreis"), price["gross"].localizedDisplayString); field(T("Nettopreis"), price["net"].localizedDisplayString) } } }
            Divider(); Text(T("Beschreibung")).font(.headline); Text(data.at("description").string ?? "–").font(.body).textSelection(.enabled)
            if !data["properties"].array.isEmpty { Divider(); Text(T("Eigenschaften")).font(.headline); ForEach(Array(data["properties"].array.enumerated()), id: \.offset) { _, entry in field(entry["group"]["name"].localizedDisplayString, entry["name"].localizedDisplayString) } }
        }
        Divider(); field("Shopware ID", data["id"].localizedDisplayString)
    }
    private func label(_ path: String) -> String { T(ListConfiguration.fields(entity).first { $0.field == path }?.title ?? ["tax.taxRate": "Steuersatz", "salesChannel.name": "Verkaufskanal"][path] ?? path) }
    private func amount(_ value: JSONValue) -> String { guard let number = value.number else { return "–" }; return currency.map { money(number, currency: $0) } ?? number.formatted(.number.locale(Locale(identifier:Language.current))) }
    private func field(_ label: String, _ value: String) -> some View { HStack(alignment: .top, spacing: 22) { Text(label).foregroundStyle(.secondary).frame(width: 180, alignment: .leading); Text(value.isEmpty ? "–" : value).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.font(.system(size: 13)) }
    @ViewBuilder private func address(_ title: String, _ value: JSONValue) -> some View {
        if value != .null { VStack(alignment: .leading, spacing: 7) { Text(title).font(.headline); Text([value["company"].string, [value["firstName"].string, value["lastName"].string].compactMap { $0 }.joined(separator: " "), value["street"].string, value["additionalAddressLine1"].string, value["additionalAddressLine2"].string, [value["zipcode"].string, value["city"].string].compactMap { $0 }.joined(separator: " "), value["country"]["name"].string, value["phoneNumber"].string].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")).font(.system(size: 13)).textSelection(.enabled) }.padding(.vertical, 6) }
    }
    private func load() async {
        loading = true; message = nil
        defer { loading = false }
        do { data = try await model.client.detail(record.shop, entity: entity, id: record.data["id"].string ?? "", resolveInheritance: true); name = data.at("name").string ?? ""; stock = String(Int(data["stock"].number ?? 0)); active = data["active"].bool ?? true; description = data.at("description").string ?? "" } catch { data = .null; message = error.localizedDescription }
    }
}
private struct JSONFieldView: View {
    let name: String
    let value: JSONValue
    var body: some View {
        Group {
            if let object = value.object { DisclosureGroup { ForEach(object.keys.sorted(), id: \.self) { key in AnyView(JSONFieldView(name: key, value: object[key] ?? .null)) }.padding(.leading, 12) } label: { Text(name + " · \(object.count)").fontWeight(.medium) } }
            else if case .array(let values) = value { DisclosureGroup { ForEach(Array(values.enumerated()), id: \.offset) { index, item in AnyView(JSONFieldView(name: "\(index + 1)", value: item)) }.padding(.leading, 12) } label: { Text(name + " · \(values.count)").fontWeight(.medium) } }
            else { HStack(alignment: .top, spacing: 20) { Text(name).foregroundStyle(.secondary).frame(width: 210, alignment: .leading); Text(value.bool.map { $0 ? T("Ja") : T("Nein") } ?? value.localizedDisplayString).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) } }
        }.font(.system(size: 12)).padding(.vertical, 4)
    }
}
