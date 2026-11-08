import SwiftUI
import DeckCore

/// An immutable snapshot taken when "add" or "duplicate" is pressed.
struct ProfileCreationRequest: Identifiable {
    let id: UUID
    let sourceProfileID: String?
    let sourceName: String?
    let copiedItems: [PinnedItem]
    var isCopy: Bool { sourceProfileID != nil }

    init(id: UUID = UUID(), sourceProfileID: String? = nil, sourceName: String? = nil, copiedItems: [PinnedItem] = []) {
        self.id = id
        self.sourceProfileID = sourceProfileID
        self.sourceName = sourceName
        self.copiedItems = copiedItems
    }
}

/// Asks for the new profile's name. Cancel changes nothing.
struct ProfileNameSheet: View {
    let request: ProfileCreationRequest
    let onConfirm: (String) -> Void
    let onCancel: () -> Void
    @State private var name = ""
    @FocusState private var focused: Bool

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(request.isCopy ? "프로필 복제" : "빈 프로필 추가").font(.headline)
            if request.isCopy, let source = request.sourceName {
                Text("‘\(source)’의 등록 항목 \(request.copiedItems.count)개를 복사합니다.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("등록 항목이 없는 새 프로필을 만듭니다.").font(.caption).foregroundStyle(.secondary)
            }
            TextField("새 프로필 이름", text: $name)
                .focused($focused)
                .onSubmit { if !trimmed.isEmpty { onConfirm(trimmed) } }
            HStack {
                Spacer()
                Button("취소", action: onCancel).keyboardShortcut(.cancelAction)
                Button(request.isCopy ? "복제" : "추가") { onConfirm(trimmed) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmed.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear { focused = true }
    }
}
