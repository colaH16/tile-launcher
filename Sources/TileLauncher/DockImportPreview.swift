import SwiftUI
import DeckCore

struct DockImportPreview: View {
    let change: DockImportChange
    let apply: () -> Void
    let cancel: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Dock에서 가져오기").font(.title2.bold())
            Text("‘\(change.profileName)’ 프로필 · \(change.addedIDs.count)개 추가")
                .font(.headline)
            Text("아래 목록을 편집 중인 프로필에 가져옵니다. 설정의 ‘저장’을 눌러야 적용하며, 기존 항목의 이름과 여는 방식은 유지합니다.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            List(change.after) { item in
                HStack(spacing: 10) {
                    if item.kind == .trash {
                        Image(systemName: "trash").font(.system(size: 22)).frame(width: 28, height: 28)
                    } else { Icon(url: item.url, size: 28) }
                    Text(item.name).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    if change.addedIDs.contains(item.id) {
                        Text("추가").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 2)
            }.frame(height: min(330, max(160, CGFloat(change.after.count) * 44 + 16)))
            if change.skipped > 0 {
                Text("사용할 수 없거나 지원하지 않는 항목 \(change.skipped)개는 건너뛰었습니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("취소", action: cancel).keyboardShortcut(.cancelAction)
                Button("가져오기", action: apply).keyboardShortcut(.defaultAction)
            }
        }.padding(20).frame(width: 460)
    }
}
