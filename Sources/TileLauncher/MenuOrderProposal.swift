import AppKit
import SwiftUI
import DeckCore

/// R215: isolated comparison fixtures retained alongside the adopted R216 UI.
struct MenuOrderProposal: View {
    let pinned: [MenuCommand]
    let collected: [MenuCommand]
    var showsEmptyPinned = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("앱").font(.caption).foregroundStyle(.secondary)
                Text("iTerm2").font(.system(size: 13, weight: .medium))
                Spacer()
                Button("메뉴 아이콘 새로고침") {}.controlSize(.small)
            }.padding(.bottom, 20)
            if !pinned.isEmpty || showsEmptyPinned {
                heading("고정", symbol: "pin.fill", count: pinned.count, detail: "직접 순서 변경")
                if pinned.isEmpty {
                    Text("메뉴 오른쪽 핀을 누르면 이곳에 표시됩니다.")
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(.top, 10).padding(.bottom, 4)
                } else {
                    ForEach(Array(pinned.enumerated()), id: \.element.id) { index, command in
                        row(command, pinnedIndex: index)
                    }
                }
                Divider().padding(.vertical, 16)
            }
            heading("자동 수집", symbol: "clock.arrow.circlepath", count: collected.count, detail: "사용 횟수 많은 순")
            ForEach(collected) { command in row(command, pinnedIndex: nil) }
        }
        .padding(24).frame(width: 580, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.colorScheme, .dark)
    }

    private func heading(_ title: String, symbol: String, count: Int, detail: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
            Text(title).fontWeight(.semibold)
            Text("\(count)개")
            Spacer()
            Text(detail)
        }.font(.caption).foregroundStyle(.secondary).padding(.bottom, 6)
    }

    private func row(_ command: MenuCommand, pinnedIndex: Int?) -> some View {
        HStack(spacing: 8) {
            MenuGlyphButton(command: command) { _ in }
            VStack(alignment: .leading, spacing: 3) {
                Text(command.title).font(.system(size: 13)).lineLimit(1)
                Text(command.path.joined(separator: " › "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                HStack(spacing: 5) {
                    if pinnedIndex == nil {
                        Text(command.isFrequent(history: .init()) ? "자주 사용" : "최근 사용")
                        Text("·")
                    }
                    Text(command.usageDescription)
                }.font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            Button {} label: { Image(systemName: command.isPinned ? "pin.fill" : "pin") }
            if let index = pinnedIndex {
                Button {} label: { Image(systemName: "chevron.up") }.disabled(index == 0)
                Button {} label: { Image(systemName: "chevron.down") }.disabled(index == pinned.count - 1)
            }
            Button {} label: { Image(systemName: "minus.circle") }
        }.buttonStyle(.borderless).padding(.vertical, 8)
    }

    static var samples: [MenuCommand] {
        func menu(_ title: String, uses: Int, pinned: Bool = false) -> MenuCommand {
            var value = MenuCommand(appID: "preview.iterm", appName: "iTerm2", path: ["Shell", title], isPinned: pinned)
            value.isAutomatic = true
            for _ in 0..<uses { value.recordUse(at: Date(), observed: true) }
            return value
        }
        return [menu("New Window with Current Profile", uses: 4), menu("New Tab", uses: 3),
                menu("New Window", uses: 1), menu("Split Vertically", uses: 8, pinned: true),
                menu("Split Horizontally", uses: 2, pinned: true)]
    }

    static var automaticallyOrdered: [MenuCommand] {
        MenuCommand.ordered(samples, appID: "preview.iterm", includingHidden: true).filter { !$0.isPinned }
    }
}
