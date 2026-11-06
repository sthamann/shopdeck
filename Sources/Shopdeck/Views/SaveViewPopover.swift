import SwiftUI

struct SaveViewEditor: View {
    var model: AppModel
    var onClose: () -> Void
    @LocalState<String> private var name = ""
    @LocalState<String?> private var error: String?
    @FocusState private var nameFocused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "bookmark").foregroundStyle(Theme.blue)
                TextField(T("Name der Ansicht"), text: $name).textFieldStyle(.roundedBorder).focused($nameFocused).onSubmit { save() }.frame(maxWidth: .infinity)
                Button(T("Abbrechen")) { onClose() }
                Button(T("Speichern")) { save() }.buttonStyle(.borderedProminent).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text(T("Shopauswahl, Suche und Filter werden zusammen gespeichert.")).font(.system(size: 11)).foregroundStyle(.secondary)
            if let error { Text(error).font(.caption).foregroundStyle(.orange) }
        }.padding(16).background(Theme.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10)).task { nameFocused = true }.onExitCommand { onClose() }
    }
    private func save() { do { try model.saveCurrentView(name: name); onClose() } catch { self.error = error.localizedDescription } }
}
