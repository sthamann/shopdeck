import SwiftUI
import AppKit
import ShopdeckCore

struct RecordTableView: NSViewRepresentable {
    var records: [ShopRecord]
    var columns: [RecordColumn]
    @Binding var selection: Set<String>
    var search: () -> Void
    var open: (ShopRecord) -> Void
    var sort:[RecordSort]
    var sortChanged:([RecordSort])->Void
    var columnsChanged: ([RecordColumn]) -> Void
    @AppStorage("compactRows") private var compact = false
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let table = KeyboardRecordTable()
        table.openRecord = { [weak coordinator = context.coordinator, weak table] in guard let table, let coordinator,coordinator.rows.indices.contains(table.selectedRow) else{return};coordinator.parent.open(coordinator.rows[table.selectedRow]) }
        table.searchRecords = { context.coordinator.parent.search() }
        table.copyRecords = { [weak coordinator = context.coordinator, weak table] in guard let table,let coordinator else{return};let rows=table.selectedRowIndexes.compactMap { coordinator.rows.indices.contains($0) ? coordinator.rows[$0] : nil };let fields=table.tableColumns.map { $0.identifier.rawValue };let text=([fields.map { field in coordinator.parent.columns.first { $0.field==field }?.title ?? field }.joined(separator:"\t")] + rows.map { record in fields.map { field in coordinator.display(record,field:field).replacingOccurrences(of:"\t",with:" ").replacingOccurrences(of:"\n",with:" ") }.joined(separator:"\t") }).joined(separator:"\n");copyText(text) }
        table.delegate = context.coordinator; table.dataSource = context.coordinator
        table.allowsMultipleSelection = true; table.allowsColumnReordering = true; table.allowsColumnResizing = true
        table.usesAlternatingRowBackgroundColors = true; table.style = .inset; table.columnAutoresizingStyle = .noColumnAutoresizing
        table.target = context.coordinator; table.doubleAction = #selector(Coordinator.doubleClick(_:))
        let scroll = NSScrollView(); scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true; scroll.autohidesScrollers = true
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let table = scroll.documentView as? NSTableView else { return }
        let c = context.coordinator; c.parent = self; c.updating = true; defer { c.updating = false }
        if table.tableColumns.map({ $0.identifier.rawValue }) != columns.map(\.field) {
            for column in table.tableColumns { table.removeTableColumn(column) }
            for column in columns { let native = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.field)); native.title = T(column.title); native.width = column.width; native.minWidth = 65; if !column.field.hasPrefix("__") && !column.field.split(separator:".").contains(where:{Int($0) != nil}){native.sortDescriptorPrototype = NSSortDescriptor(key: column.field, ascending: true)}else if column.field=="__image"{native.headerToolTip=T("Produktbild")}else{native.headerToolTip=T("Dieses strukturierte Preisfeld bietet keine direkte API Sortierung.")}; table.addTableColumn(native) }
        } else { for (native, column) in zip(table.tableColumns, columns) { native.title = T(column.title) } }
        let expectedSort=sort.map{NSSortDescriptor(key:$0.field,ascending:$0.ascending)}
        if table.sortDescriptors != expectedSort {table.sortDescriptors=expectedSort}
        table.rowHeight = compact ? 30 : 40
        if c.originalRecords != records || c.previousColumns != columns || c.language != Language.current {
            c.originalRecords=records;c.previousColumns=columns;c.language=Language.current
            c.rows=records
            table.reloadData()
        }
        let expected=IndexSet(c.rows.indices.filter {selection.contains(c.rows[$0].id)})
        if table.selectedRowIndexes != expected {table.selectRowIndexes(expected,byExtendingSelection:false)}
    }
    @MainActor final class Coordinator: NSObject, NSTableViewDelegate, NSTableViewDataSource {
        var parent: RecordTableView
        var rows: [ShopRecord] = []
        var originalRecords:[ShopRecord]=[]
        var previousColumns:[RecordColumn]=[]
        var language=""
        var updating = false
        private var pendingColumnSave:DispatchWorkItem?
        init(_ parent: RecordTableView) { self.parent = parent }
        func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard rows.indices.contains(row), let column = tableColumn else { return nil }
            if column.identifier.rawValue=="__image"{let id=NSUserInterfaceItemIdentifier("product-thumbnail");let cell=tableView.makeView(withIdentifier:id,owner:self) as? ProductThumbnailCell ?? ProductThumbnailCell(frame:.zero);cell.identifier=id;cell.configure(rows[row]);return cell}
            let identifier = NSUserInterfaceItemIdentifier("record-cell-"+column.identifier.rawValue)
            let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? {
                let view = NSTableCellView(); view.identifier = identifier
                let text = NSTextField(labelWithString: ""); text.lineBreakMode = .byTruncatingTail; text.maximumNumberOfLines=1; text.cell?.wraps=false; text.cell?.isScrollable=false; text.usesSingleLineMode=true; text.setContentCompressionResistancePriority(.defaultLow,for:.horizontal); text.translatesAutoresizingMaskIntoConstraints = false
                view.addSubview(text); view.textField = text
                NSLayoutConstraint.activate([text.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8), text.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8), text.centerYAnchor.constraint(equalTo: view.centerYAnchor)])
                return view
            }()
            let record = rows[row], field = column.identifier.rawValue
            cell.textField?.stringValue = display(record, field: field)
            cell.textField?.font = .systemFont(ofSize: 12, weight: field == "name" || field == "orderNumber" ? .medium : .regular)
            cell.textField?.textColor = .labelColor
            cell.toolTip = cell.textField?.stringValue
            return cell
        }
        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !updating, let table = notification.object as? NSTableView else { return }
            parent.selection = Set(table.selectedRowIndexes.compactMap { rows.indices.contains($0) ? rows[$0].id : nil })
        }
        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard !updating else{return}
            let next=tableView.sortDescriptors.compactMap{descriptor in descriptor.key.map{RecordSort($0,ascending:descriptor.ascending)}}
            parent.sortChanged(next)
        }
        func tableView(_ tableView:NSTableView,shouldReorderColumn columnIndex:Int,toColumn newIndex:Int)->Bool {tableView.tableColumns[columnIndex].identifier.rawValue != "__image" && tableView.tableColumns[newIndex].identifier.rawValue != "__image"}
        func tableViewColumnDidMove(_ notification: Notification) { persistColumns(notification) }
        func tableViewColumnDidResize(_ notification: Notification) { persistColumns(notification) }
        private func persistColumns(_ notification: Notification) {
            guard !updating, let table = notification.object as? NSTableView else { return }
            let columns = table.tableColumns.compactMap { native -> RecordColumn? in guard var column = parent.columns.first(where: { $0.field == native.identifier.rawValue }) else { return nil }; column.width = native.width; return column }
            let callback = parent.columnsChanged
            pendingColumnSave?.cancel();let item=DispatchWorkItem{callback(columns)};pendingColumnSave=item;DispatchQueue.main.asyncAfter(deadline:.now()+0.25,execute:item)
        }
        @objc func doubleClick(_ table: NSTableView) { guard rows.indices.contains(table.clickedRow) else { return }; parent.open(rows[table.clickedRow]) }
        func display(_ record: ShopRecord, field: String) -> String {
            if field == "shop" { return record.shop.name }
            let value = record.data.at(field)
            if let b = value.bool { return b ? T("Ja") : T("Nein") }
            if ["createdAt", "updatedAt", "orderDateTime"].contains(field), value != .null { return dateLabel(value) }
            if ["amountTotal", "amountNet", "shippingTotal"].contains(field), let n = value.number, let currency = record.data["currency"]["isoCode"].string { return money(n, currency: currency) }
            if field == "stateMachineState.technicalName", let status = value.string { return T(status) }
            return value.localizedDisplayString
        }
    }
}

private final class KeyboardRecordTable: NSTableView {
    var openRecord: (() -> Void)?
    var copyRecords: (() -> Void)?
    var searchRecords: (() -> Void)?
    override func keyDown(with event:NSEvent) {
        if event.modifierFlags.contains(.command),event.charactersIgnoringModifiers=="c" { copyRecords?();return }
        if event.modifierFlags.contains(.command),event.charactersIgnoringModifiers=="f" { searchRecords?();return }
        if event.keyCode==36 || event.keyCode==76 || event.keyCode==49 { openRecord?();return }
        if event.keyCode==53 { deselectAll(nil);return }
        super.keyDown(with:event)
    }
}
