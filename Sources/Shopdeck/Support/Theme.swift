import SwiftUI
import ShopdeckCore

// Disambiguate the property wrapper from the newer SDK State macro.
typealias LocalState<Value> = SwiftUI.State<Value>

enum Theme {
    static let blue = Color(nsColor: NSColor(name: NSColor.Name("ShopdeckAccent")) { appearance in appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(srgbRed:24/255,green:158/255,blue:1,alpha:1) : NSColor(srgbRed:0,green:104/255,blue:214/255,alpha:1) })
    static let deep = Color(red: 1/255, green: 118/255, blue: 1)
    static let navy = Color(red: 6/255, green: 50/255, blue: 95/255)
    static let pale = Color(red: 227/255, green: 243/255, blue: 1)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static func color(_ name: String) -> Color { switch name { case "orange": return .orange; case "mint": return .mint; case "purple": return .purple; default: return blue } }
}
struct ShopIcon: View {
    let shop: Shop
    var size: CGFloat = 32
    var body: some View {
        Group {
            if let file = shop.faviconFile, let image = NSImage(contentsOfFile: file) { Image(nsImage: image).resizable().scaledToFit().padding(4) }
            else { Text(shop.initials).font(.system(size: size * 0.35, weight: .bold, design: .rounded)).foregroundStyle(Theme.color(shop.color)) }
        }.frame(width: size, height: size).background(Theme.color(shop.color).opacity(0.13), in: RoundedRectangle(cornerRadius: size * 0.27)).accessibilityLabel(shop.name)
    }
}
struct StatusPill: View {
    let text: String
    var color: Color = .green
    var body: some View { HStack(spacing: 5) { Circle().fill(color).frame(width: 5, height: 5); Text(text).font(.system(size: 11, weight: .medium)).lineLimit(1).fixedSize() }.padding(.horizontal, 9).padding(.vertical, 5).foregroundStyle(color).background(color.opacity(0.1), in: Capsule()) }
}
struct Panel<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View { content.padding(22).background(Theme.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 14)) }
}
struct PageTitle: View {
    let title: String
    let subtitle: String
    var body: some View { VStack(alignment: .leading, spacing: 8) { Text(title).font(.system(size: 30, weight: .bold)); Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary) } }
}
func money(_ number: Double, currency: String = "EUR") -> String { number.formatted(.currency(code: currency).locale(Locale(identifier: Language.current))) }
func dateLabel(_ value: JSONValue) -> String { guard let s = value.string else { return "–" }; let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; guard let d = formatter.date(from: s) ?? ISO8601DateFormatter().date(from: s) else { return s }; return d.formatted(.dateTime.day().month().hour().minute().locale(Locale(identifier: Language.current))) }
func copyText(_ value: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(value, forType: .string) }

func localizedDate(_ date:Date,date style:Date.FormatStyle.DateStyle = .abbreviated,time:Date.FormatStyle.TimeStyle = .shortened)->String{date.formatted(Date.FormatStyle(date:style,time:time).locale(Locale(identifier:Language.current)))}

// Keeps custom sidebar and tab hit targets consistent with native controls.
struct WorkspaceRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Row(configuration: configuration)
    }

    private struct Row: View {
        let configuration: ButtonStyle.Configuration
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.isEnabled) private var enabled
        @LocalState<Bool> private var hovering = false

        var body: some View {
            configuration.label
                .background(
                    Color.primary.opacity(enabled ? (configuration.isPressed ? 0.12 : hovering ? 0.055 : 0) : 0),
                    in: RoundedRectangle(cornerRadius: 7)
                )
                .onHover { hovering = $0 }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: configuration.isPressed)
        }
    }
}
