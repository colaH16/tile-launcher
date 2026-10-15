import AppKit
import SwiftUI
import DeckCore

/// Small row control in Settings → Menu. The tile shows the chosen SF Symbol,
/// otherwise the shortcut, otherwise the title as large text.
struct MenuGlyphButton: View {
    let command: MenuCommand
    let choose: (String?) -> Void
    @State private var editing = false
    var body: some View {
        Button { editing = true } label: { MenuGlyphPreview(glyph: command.glyph).frame(width: 34, height: 26) }
            .buttonStyle(.bordered).controlSize(.small)
            .help("오버레이 타일 아이콘 · SF Symbol 선택. 없으면 단축키, 둘 다 없으면 메뉴 이름을 크게 표시")
            .accessibilityLabel("\(command.title) 아이콘 선택")
            .popover(isPresented: $editing, arrowEdge: .leading) {
                MenuSymbolPicker(command: command, choose: { choose($0); editing = false })
            }
    }
}

struct MenuGlyphPreview: View {
    let glyph: MenuTileGlyph
    var body: some View {
        switch glyph {
        case .symbol(let name): Image(systemName: name).font(.system(size: 14))
        case .shortcut(let keys): Text(keys).font(.system(size: 10, weight: .medium, design: .rounded)).lineLimit(1).minimumScaleFactor(0.6)
        case .text: Image(systemName: "textformat").font(.system(size: 13)).foregroundStyle(.secondary)
        }
    }
}

struct MenuSymbolPicker: View {
    let command: MenuCommand
    let choose: (String?) -> Void
    @State private var name: String
    init(command: MenuCommand, choose: @escaping (String?) -> Void) {
        self.command = command; self.choose = choose
        _name = State(initialValue: command.symbol ?? "")  // "" also for “no icon”
    }
    /// A starting set only; any installed SF Symbol name can be typed.
    static let suggestions = [
        "plus", "plus.square.on.square", "doc.badge.plus", "folder.badge.plus", "macwindow.badge.plus",
        "folder", "doc", "doc.on.doc", "doc.on.clipboard", "scissors",
        "square.and.arrow.up", "square.and.arrow.down", "printer", "magnifyingglass", "info.circle",
        "gearshape", "trash", "pencil", "arrow.uturn.backward", "arrow.uturn.forward",
        "arrow.clockwise", "sidebar.left", "macwindow", "rectangle.split.2x1", "server.rack",
        "link", "bookmark", "star", "heart", "tag",
        "paperplane", "envelope", "photo", "music.note", "play",
        "film", "tv", "calendar", "clock", "list.bullet",
        "checkmark.circle", "xmark.circle", "eye", "eye.slash", "lock",
        "terminal", "hammer", "wand.and.stars"
    ]
    private var trimmed: String? { MenuSymbolName.normalized(name) }
    private var valid: Bool { trimmed.map { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil } ?? false }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(command.title) 아이콘").font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 4), count: 10), spacing: 4) {
                ForEach(Self.suggestions, id: \.self) { symbol in
                    Button { name = symbol } label: { Image(systemName: symbol).frame(width: 26, height: 22) }
                        .buttonStyle(.borderless)
                        .background(trimmed == symbol ? Color.accentColor.opacity(0.25) : .clear, in: RoundedRectangle(cornerRadius: 5))
                        .help(symbol)
                }
            }
            HStack {
                TextField("SF Symbol 이름 (예: folder.badge.plus)", text: $name).textFieldStyle(.roundedBorder)
                    .onSubmit { if valid { choose(trimmed) } }
                Group {
                    if valid, let trimmed { Image(systemName: trimmed) } else { Image(systemName: "questionmark.square.dashed").foregroundStyle(.secondary) }
                }.font(.system(size: 18)).frame(width: 26)
            }
            Text(trimmed != nil && !valid ? "이 macOS에 없는 심볼 이름입니다." :
                 "SF Symbols 앱에서 이름을 복사해 붙여 넣을 수도 있어요. 아이콘이 없으면 단축키, 단축키도 없으면 메뉴 이름을 크게 표시합니다.")
                .font(.caption).foregroundStyle(trimmed != nil && !valid ? .red : .secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let preset = command.presetSymbol {
                Label("기본 아이콘: \(preset)", systemImage: preset).font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("기본값") { choose(nil) }
                    .help(command.presetSymbol == nil ? "직접 고른 아이콘을 지웁니다" : "직접 고른 아이콘을 지우고 기본 아이콘을 씁니다")
                Button("아이콘 없음") { choose(MenuSymbolName.hidden) }
                    .help("기본 아이콘도 쓰지 않고 단축키나 메뉴 이름을 표시합니다")
                Spacer()
                Button("적용") { choose(trimmed) }.keyboardShortcut(.defaultAction).disabled(!valid)
            }
        }.padding(14).frame(width: 360)
    }
}
