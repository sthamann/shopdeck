import SwiftUI
import PDFKit
import ShopdeckCore
import UniformTypeIdentifiers

struct OrderDocumentSelection: Identifiable { let id = UUID(); let orders: [ShopRecord] }
struct OrderDocumentsView: View {
    var model: AppModel
    let orders: [ShopRecord]
    @Environment(\.dismiss) private var dismiss
    @LocalState<[OrderDocument]> private var documents = []
    @LocalState<Set<String>> private var selection = []
    @LocalState<Data?> private var pdf = nil
    @LocalState<String?> private var pdfID = nil
    @LocalState<Bool> private var loading = true
    @LocalState<Bool> private var loadingPDF = false
    @LocalState<String?> private var error = nil
    @LocalState<String?> private var pdfError = nil
    @LocalState<String> private var search = ""
    @LocalState<Int> private var total = 0
    @LocalState<Bool> private var exporting = false
    @LocalState<String> private var exportProgress = ""
    @LocalState<Task<Void, Never>?> private var exportTask = nil
    private var selectedDocuments: [OrderDocument] { documents.filter { selection.contains($0.id) } }
    private var previewDocument: OrderDocument? { selectedDocuments.first }
    private var visibleDocuments: [OrderDocument] {
        documents.filter { search.isEmpty || [$0.number, $0.shop.name, documentTitle($0.type)].joined(separator: " ").localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "doc.richtext").font(.system(size: 26)).foregroundStyle(Theme.blue)
                VStack(alignment: .leading, spacing: 5) { Text(T("Bestelldokumente")).font(.title2.bold()); Text("\(orders.count) " + T("Bestellungen") + " · \(documents.count) " + T("Dokumente")).font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }.help(T("Aktualisieren")).disabled(loading || exporting)
                Button(T("Schließen")) { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(22)
            Divider()
            HSplitView {
                VStack(alignment: .leading, spacing: 12) {
                    TextField(T("Nummer, Dokumenttyp oder Shop suchen"), text: $search).textFieldStyle(.roundedBorder)
                    if loading { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
                    else if documents.isEmpty { ContentUnavailableView(T("Noch keine Dokumente"), systemImage: "doc", description: Text(T("Vorhandene Rechnungen, Lieferscheine und Gutschriften erscheinen hier. Neue Dokumente erstellst du in Shopware."))).frame(maxHeight: .infinity) }
                    else {
                        List(visibleDocuments, selection: $selection) { document in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "doc.text").foregroundStyle(Theme.blue)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(documentTitle(document.type)).font(.system(size: 13, weight: .semibold))
                                    Text(document.number).font(.system(size: 12)).textSelection(.enabled)
                                    Text(document.shop.name).font(.system(size: 11)).foregroundStyle(.secondary)
                                }
                            }.padding(.vertical, 7).tag(document.id)
                        }.listStyle(.inset)
                    }
                    if total > documents.count { Text(T("Mehr als 1.000 Dokumente. Wähle weniger Bestellungen für ein vollständiges Paket.")).font(.caption).foregroundStyle(.orange) }
                    if let error { Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
                    Text(T("Mit ⌘ oder ⇧ mehrere Dokumente für ein Paket auswählen.")).font(.caption).foregroundStyle(.secondary)
                }.padding(18).frame(minWidth: 250, idealWidth: 280, maxWidth: 330)
                VStack(spacing: 0) {
                    if loadingPDF { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
                    else if let pdf { NativePDFView(data: pdf).frame(maxWidth: .infinity, maxHeight: .infinity) }
                    else { ContentUnavailableView(T("Dokumentvorschau"), systemImage: "doc.viewfinder", description: Text(pdfError ?? T("Wähle ein Dokument aus der Liste."))).frame(maxWidth: .infinity, maxHeight: .infinity) }
                    if let doc = previewDocument, doc.shop.isDemo { Text(T("Demodokument. Keine echte Rechnung.")).font(.caption).foregroundStyle(.orange).padding(10) }
                }.frame(minWidth: 450)
            }
            Divider()
            HStack(spacing: 12) {
                if exporting { ProgressView().controlSize(.small); Text(exportProgress).font(.caption); Button(T("Abbrechen")) { exportTask?.cancel() } }
                else { Text(T("Originale bleiben unverändert. Mehrere PDFs werden als ZIP Paket gespeichert.")).font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button(T("Alle auswählen")) { selection = Set(visibleDocuments.map(\.id)) }.disabled(documents.isEmpty || exporting)
                Button { export() } label: { Label(T(selectedDocuments.count > 1 ? "Dokumentenpaket speichern" : "PDF speichern"), systemImage: "square.and.arrow.down") }.buttonStyle(.borderedProminent).disabled(selection.isEmpty || exporting || loading)
            }.padding(18)
        }.frame(width: 1000, height: 740)
            .task { await load() }
            .task(id: previewDocument?.id) { await loadPreview() }
            .onDisappear { exportTask?.cancel() }
    }
    private func load() async {
        loading = true; error = nil; defer { loading = false }
        var result: [OrderDocument] = [], count = 0, failures: [String] = []
        let groups = Dictionary(grouping: orders, by: { $0.shop.id }).values.sorted { $0[0].shop.name < $1[0].shop.name }
        for group in groups {
            do { let page = try await model.client.orderDocuments(group[0].shop, orderIDs: group.compactMap { $0.data["id"].string }); result += page.documents; count += page.total }
            catch { failures.append(group[0].shop.name + ": " + error.localizedDescription) }
        }
        guard !Task.isCancelled else { return }
        documents = result; total = count; selection = selection.intersection(result.map(\.id))
        if selection.isEmpty, let first = result.first { selection = [first.id] }
        error = failures.isEmpty ? nil : failures.joined(separator: "\n")
    }
    private func loadPreview() async {
        guard let document = previewDocument else { pdf = nil; pdfID = nil; pdfError = nil; loadingPDF = false; return }
        if pdfID == document.id && pdf != nil { return }
        loadingPDF = true; pdf = nil; pdfError = nil; defer { if previewDocument?.id == document.id { loadingPDF = false } }
        do {
            let data = try await model.client.downloadDocument(document); try Task.checkCancellation()
            guard previewDocument?.id == document.id else { return }
            guard PDFDocument(data: data) != nil else { throw ShopdeckError.message(T("Dieses PDF konnte nicht gelesen werden.")) }
            pdf = data; pdfID = document.id
        } catch is CancellationError { }
        catch { guard !Task.isCancelled, previewDocument?.id == document.id else { return }; pdfError = error.localizedDescription }
    }
    private func export() {
        let chosen = selectedDocuments
        guard !chosen.isEmpty else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = chosen.count == 1 ? [.pdf] : [.zip]
        panel.nameFieldStringValue = chosen.count == 1 ? chosen[0].filename : "Shopdeck-Documents.zip"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        let cached = pdf, cachedID = pdfID
        exporting = true; error = nil
        exportTask = Task { @MainActor in
            defer { exporting = false; exportTask = nil }
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("shopdeck-documents-" + UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: folder) }
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                var totalBytes = 0
                for (index, document) in chosen.enumerated() {
                    try Task.checkCancellation(); exportProgress = "\(index + 1) / \(chosen.count)"
                    let bytes: Data
                    if cachedID == document.id, let cached { bytes = cached } else { bytes = try await model.client.downloadDocument(document) }
                    try Task.checkCancellation(); totalBytes += bytes.count
                    guard totalBytes <= 256 * 1024 * 1024 else { throw ShopdeckError.message(T("Das Paket überschreitet 256 MB. Wähle weniger Dokumente.")) }
                    if chosen.count == 1 { try bytes.write(to: destination, options: .atomic) }
                    else {
                        let group = folder.appendingPathComponent(document.archiveDirectory)
                        try FileManager.default.createDirectory(at: group, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                        let filename = document.documentID + "-" + document.filename
                        let file = group.appendingPathComponent(filename); try bytes.write(to: file, options: .atomic)
                        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
                    }
                }
                if chosen.count > 1 {
                    let archive = folder.deletingLastPathComponent().appendingPathComponent(folder.lastPathComponent + ".zip")
                    defer { try? FileManager.default.removeItem(at: archive) }
                    try await Task.detached {
                        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto"); process.arguments = ["-c", "-k", "--norsrc", "--noextattr", "--noqtn", folder.path, archive.path]
                        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
                        try process.run(); process.waitUntilExit()
                        guard process.terminationStatus == 0 else { throw ShopdeckError.message("ZIP export failed.") }
                    }.value
                    try Task.checkCancellation()
                    try Data(contentsOf: archive, options: .mappedIfSafe).write(to: destination, options: .atomic)
                }
                model.notice = "\(chosen.count) " + T("Dokumente gespeichert")
            } catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }
    private func documentTitle(_ type: String) -> String { T(["invoice": "Rechnung", "delivery_note": "Lieferschein", "credit_note": "Gutschrift", "storno": "Stornorechnung"][type] ?? type) }
}
private struct NativePDFView: NSViewRepresentable {
    let data: Data
    final class Coordinator { var data: Data? }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> PDFView { let view = PDFView(); view.autoScales = true; view.displayMode = .singlePageContinuous; view.backgroundColor = .controlBackgroundColor; return view }
    func updateNSView(_ view: PDFView, context: Context) { if context.coordinator.data != data { view.document = PDFDocument(data: data); context.coordinator.data = data } }
}
