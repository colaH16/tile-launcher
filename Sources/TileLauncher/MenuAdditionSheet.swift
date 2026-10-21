import SwiftUI
import DeckCore

enum MenuAdditionLayout {
    static func size(for parent: CGSize) -> CGSize {
        CGSize(width: min(540, max(360, parent.width - 40)), height: max(360, parent.height - 64))
    }
}

/// Shared by the native sheet and the offscreen layout preview.
struct MenuAdditionSheet: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var catalog: MenuCatalog
    @Binding var selectedID: String
    @Binding var search: String
    @Binding var manualPath: String
    let appNames: [(id: String, name: String)]
    let selectedApp: AppItem?
    let size: CGSize
    let refreshApps: () -> Void
    let dismiss: () -> Void
    @State var manualExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("메뉴 추가").font(.title2.weight(.semibold))
                Spacer()
                Button("완료", action: dismiss).keyboardShortcut(.cancelAction)
            }
            HStack {
                Picker("앱", selection: $selectedID) {
                    if selectedID.isEmpty { Text("앱 선택").tag("") }
                    ForEach(appNames, id: \.id) { Text($0.name).tag($0.id) }
                }
                Button("앱 목록 새로고침", action: refreshApps)
            }
            if selectedApp == nil {
                Text("메뉴를 추가할 앱을 실행한 뒤 선택해 주세요.").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Text("앱의 메뉴 막대에서 선택").font(.headline)
                Spacer()
                Button(catalog.loading ? "읽는 중…" : "선택한 앱의 메뉴 불러오기") {
                    if let app = selectedApp { catalog.load(app: app) }
                }.disabled(selectedApp == nil || catalog.loading)
            }
            TextField("메뉴 검색", text: $search)
            if let message = catalog.message { Text(message).font(.caption).foregroundStyle(.secondary) }
            List {
                ForEach(catalog.choices.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }) { menu in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(menu.title).font(.callout).lineLimit(2)
                            if let variant = menu.variantLabel {
                                Text(variant).font(.caption).foregroundStyle(.secondary)
                            } else if menu.needsDisambiguation, let identifier = menu.axIdentifier {
                                Text(identifier).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        Spacer()
                        let existing = settings.commands.first { $0.appID == selectedID && $0.path == menu.path }
                        let added = existing != nil && existing?.axIdentifier == menu.axIdentifier && existing?.optionAction == menu.optionAction
                        Button(added ? "등록됨" : existing != nil ? "대상 변경" : "추가") {
                            if let app = selectedApp {
                                var command = MenuCommand(appID: app.id, appName: app.name, path: menu.path)
                                command.shortcut = menu.shortcut
                                command.axIdentifier = menu.axIdentifier
                                command.optionAction = menu.optionAction
                                settings.addCommand(command, replacingTarget: true)
                            }
                        }.disabled(added)
                    }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            DisclosureGroup("메뉴 경로 직접 입력", isExpanded: $manualExpanded) {
                HStack {
                    TextField("예: 파일 > 내보내기 > PDF로 내보내기…", text: $manualPath)
                    Button("추가") {
                        let path = manualPath.components(separatedBy: ">").map { $0.trimmingCharacters(in: .whitespaces) }
                        if let app = selectedApp, path.count >= 2, path.allSatisfy({ !$0.isEmpty }) {
                            settings.addCommand(MenuCommand(appID: app.id, appName: app.name, path: path)); manualPath = ""
                        }
                    }.disabled(selectedApp == nil || !manualPath.contains(">"))
                }.padding(.top, 6)
            }
        }.padding(20).frame(width: size.width, height: size.height)
    }
}
