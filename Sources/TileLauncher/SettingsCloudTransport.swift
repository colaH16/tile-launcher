import CloudKit
import Foundation

/// The engine schedules network work; the coordinator owns semantic merge and
/// atomic persistence. Each instance belongs to one confirmed account/session.
actor SettingsCloudTransport: CKSyncEngineDelegate {
    nonisolated let id = UUID()
    private weak var owner: SettingsSyncCoordinator?
    private var engine: CKSyncEngine?
    static let zone = CKRecordZone.ID(zoneName: "TileLauncherSettings")
    init(owner: SettingsSyncCoordinator) { self.owner = owner }
    func start(database: CKDatabase, state: CKSyncEngine.State.Serialization?) {
        let config = CKSyncEngine.Configuration(database: database, stateSerialization: state, delegate: self)
        engine = CKSyncEngine(config)
    }
    func fetch() async throws { try await engine?.fetchChanges() }
    func enqueue(_ names: [String], createZone: Bool = false) {
        if createZone { engine?.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zone))]) }
        engine?.state.add(pendingRecordZoneChanges: names.map { .saveRecord(.init(recordName: $0, zoneID: Self.zone)) })
    }
    func stop() async {
        let old = engine; engine = nil
        await old?.cancelOperations()
    }
    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        guard engine === syncEngine else { return }
        await owner?.handle(event, transport: self)
    }
    func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        guard engine === syncEngine, let owner else { return nil }
        let records = await owner.outgoingRecords(session: id)
        guard !records.isEmpty else { return nil }
        let changes = syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
        return await .init(pendingChanges: changes) { recordID in records[recordID.recordName] }
    }
}
