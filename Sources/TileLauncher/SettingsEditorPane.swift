import SwiftUI

struct SettingsEditorPane<Content: View>: View {
    @ObservedObject var session: SettingsEditingSession
    @ObservedObject var draft: SettingsStore
    let tab: SettingsTab
    var onCancel: () -> Void = {}
    @ViewBuilder let content: (SettingsStore) -> Content
    var body: some View {
        VStack(spacing: 0) {
            SyncEditingGate(status: session.syncStatus, gated: tab == .appearance) {
                content(draft).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            VStack(spacing: 10) {
                Divider()
                HStack {
                    Text(session.errors[tab] ?? (session.hasChanges(tab) ? "저장하지 않은 변경사항" : "저장됨"))
                        .font(.caption)
                        .foregroundStyle(session.errors[tab] == nil ? Color.secondary : Color.red)
                    Spacer(minLength: 8)
                    Button("변경 취소") { session.cancel(tab); onCancel() }
                        .disabled(!session.hasChanges(tab))
                    SyncEditingGate(status: session.syncStatus, gated: tab == .appearance || tab == .menus) {
                        Button("저장") { session.save(tab) }.disabled(!session.canSave(tab))
                    }
                        .buttonStyle(.borderedProminent)
                }
            }.padding(.horizontal, SettingsSpacing.paneInset).padding(.vertical, 10)
        }
        .onAppear { if tab == .menus { session.activateMenuIcons() } }
    }
}
