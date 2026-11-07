import SwiftUI
import ShopdeckCore
struct OnboardingView:View {
    var model:AppModel
    var completion:(Bool)->Void
    var exploreDemo: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("language") private var language=AppLanguage.initial()
    @AppStorage("appearance") private var appearance="system"
    @LocalState<Int> private var step=0
    @LocalState<Bool> private var connecting=false
    @LocalState<Bool> private var openAI=false
    private let titles=["Willkommen bei Shopdeck","Dein erster Shop","Dein KI Zugang","Dein Arbeitsplatz ist bereit"]
    var body:some View {
        VStack(alignment:.leading,spacing:24){
            HStack{Image(nsImage:Bundle.main.url(forResource:"AppIcon",withExtension:"icns").flatMap{NSImage(contentsOf:$0)} ?? NSImage(systemSymbolName:"bag",accessibilityDescription:nil) ?? NSImage()).resizable().frame(width:46,height:46);Text("shopdeck").font(.system(size:24,weight:.bold,design:.rounded));Spacer();Text("\(step+1) / 4").font(.caption).foregroundStyle(.secondary)}
            ProgressView(value:Double(step+1),total:4).tint(Theme.blue)
            Text(T(titles[step])).font(.system(size:29,weight:.bold,design:.rounded))
            Group{switch step {
            case 0:VStack(alignment:.leading,spacing:20){Text(T("Ein paar Schritte, dann sind deine Shops und Werkzeuge an einem Ort.")).foregroundStyle(.secondary);Picker(T("Sprache"),selection:$language){ForEach(Language.all,id:\.0){Text($0.1).tag($0.0)}};Picker(T("Erscheinungsbild"),selection:$appearance){Text(T("System")).tag("system");Text(T("Hell")).tag("light");Text(T("Dunkel")).tag("dark")}.pickerStyle(.segmented);Text(T("Die Computersprache ist vorausgewählt. Nicht verfügbare Sprachen verwenden Englisch.")).font(.caption).foregroundStyle(.secondary)}
            case 1:VStack(alignment:.leading,spacing:16){Text(T("Verbinde deinen Shop oder starte einen lokalen Shop zum Ausprobieren.")).foregroundStyle(.secondary);onboardingAction("link",T("Bestehenden Shop verbinden"),T("Mit deiner Shopadresse und einer Shopware Integration.")){model.startWithLocalShop=false;connecting=true};onboardingAction("shippingbox",T("Lokalen Testshop erstellen"),T("Shopdeck übernimmt Docker, freien Port und API Einrichtung.")){model.startWithLocalShop=true;connecting=true};Button(T("Mit Demodaten erkunden")){Task{await model.addDemo();if !model.workspace.shops.isEmpty { move(to: 2) }}}.buttonStyle(.borderless);ForEach(model.workspace.shops){shop in Label(shop.name,systemImage:"checkmark.circle.fill").foregroundStyle(.green)}}
            case 2:VStack(alignment:.leading,spacing:20){Text(T("Codex und Claude können deine freigegebenen Shops lesen und Änderungen zur Prüfung vorschlagen.")).foregroundStyle(.secondary);ForEach(model.workspace.shops){shop in Toggle(shop.name,isOn:Binding(get:{model.workspace.shops.first{$0.id==shop.id}?.mcpEnabled ?? false},set:{enabled in model.mutate{state in if let index=state.shops.firstIndex(where:{$0.id==shop.id}){state.shops[index].mcpEnabled=enabled}}}))};Toggle(T("Anschließend Codex und Claude einrichten"),isOn:$openAI);Text(T("Kundendaten bleiben ohne separate Freigabe verborgen. Du kannst den KI Zugang später ändern.")).font(.caption).foregroundStyle(.secondary)}
            default:VStack(alignment:.leading,spacing:20){Label(T("Shops verbunden"),systemImage:"checkmark.circle.fill").foregroundStyle(.green);Text(T("Passe dein Dashboard an, richte Bestellregeln ein und wähle deine Desktop Widgets.")).foregroundStyle(.secondary);Label(T("Alle Shops anzeigen setzt den Shopfilter in jeder Ansicht zurück."),systemImage:"line.3.horizontal.decrease.circle");Label(T("Änderungen werden vor der Übernahme in Shopdeck geprüft."),systemImage:"checkmark.shield")}
            }}.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
            Divider()
            HStack {
                if step > 0 {
                    Button(T("Zurück")) { move(to: step - 1) }
                } else {
                    Button(T("Später einrichten")) { completion(false) }
                    Button(T("Mit Demodaten erkunden"), action: exploreDemo)
                }
                Spacer()
                Button(step == 3 ? T("Shopdeck öffnen") : T("Fortfahren")) {
                    if step == 3 { completion(openAI) } else { move(to: step + 1) }
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(step == 1 && model.workspace.shops.isEmpty)
            }
        }.padding(30).frame(width:660,height:590).interactiveDismissDisabled()
        .sheet(isPresented:$connecting){ShopFormView(model:model,existing:nil)}
    }
    private func move(to next: Int) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { step = next }
    }
    private func onboardingAction(_ icon:String,_ title:String,_ detail:String,action:@escaping()->Void)->some View {Button(action:action){HStack(spacing:15){Image(systemName:icon).font(.system(size:24)).foregroundStyle(Theme.blue).frame(width:36);VStack(alignment:.leading,spacing:5){Text(title).font(.system(size:14,weight:.semibold));Text(detail).font(.system(size:12)).foregroundStyle(.secondary)};Spacer();Image(systemName:"chevron.right").foregroundStyle(.secondary)}.padding(17).background(Theme.surface,in:RoundedRectangle(cornerRadius:11))}.buttonStyle(.plain)}
}
