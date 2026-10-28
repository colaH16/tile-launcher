import CloudKit
import Foundation

/// The engine schedules network work; the coordinator owns semantic merge and
/// atomic persistence. Each instance belongs to one confirmed account/session.
actor SettingsCloudTransport: CKSyncEngineDelegate {
    nonisolated let id = UUID()
    private weak var owner: SettingsSyncCoordinator?
    private var engine: CKSyncEngine?
    /// Once stopped, a late `start` must not create an orphan engine.
    private var stopped = false
    static let zone = CKRecordZone.ID(zoneName: "TileLauncherSettings")
    init(owner: SettingsSyncCoordinator) { self.owner = owner }
    func start(database: CKDatabase, state: CKSyncEngine.State.Serialization?) {
        guard !stopped, engine == nil else { return }
        let config = CKSyncEngine.Configuration(database: database, stateSerialization: state, delegate: self)
        engine = CKSyncEngine(config)
    }
    func fetch() async throws { try await engine?.fetchChanges() }
    func enqueue(_ names: [String], createZone: Bool = false) {
        if createZone { engine?.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zone))]) }
        engine?.state.add(pendingRecordZoneChanges: names.map { .saveRecord(.init(recordName: $0, zoneID: Self.zone)) })
    }
    func stop() async {
        stopped = true
        let old = engine; engine = nil
        await old?.cancelOperations()
    }
    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        guard engine === syncEngine else { return }
        await owner?.handle(event, transport: self)
    }
    func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        guard engine === syncEngine, !stopped, let owner else { return nil }
        let records = await owner.outgoingRecords(session: id)
        guard engine === syncEngine, !stopped else { return nil }
        let changes = syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
        // As in Apple's sample, a pending save that cannot be provided now
        // (before the first merge, quarantined, rejected or paused) is removed
        // instead of being offered again; the coordinator's persisted outbox
        // queues it again when it can be sent.
        var available: [CKSyncEngine.PendingRecordZoneChange] = [], unavailable: [CKSyncEngine.PendingRecordZoneChange] = []
        for change in changes {
            if case .saveRecord(let recordID) = change, records[recordID.recordName] == nil { unavailable.append(change) }
            else { available.append(change) }
        }
        if !unavailable.isEmpty { syncEngine.state.remove(pendingRecordZoneChanges: unavailable) }
        guard !available.isEmpty else { return nil }
        let batch = await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: available) { recordID in records[recordID.recordName] }
        // Both cross-actor access and batch construction can suspend. A stop
        // that arrived during either await must also veto the old batch.
        guard engine === syncEngine, !stopped else { return nil }
        return batch
    }
}
