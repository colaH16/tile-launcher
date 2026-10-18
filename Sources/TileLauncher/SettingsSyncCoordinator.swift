import AppKit
import CloudKit
import CryptoKit
import DeckCore
import Security

private struct CloudAccountState: Codable {
    var engine: CKSyncEngine.State.Serialization?
    var serverRecords: [String: Data] = [:]
    var remote = SettingsSyncSnapshot()
    var dirty: Set<String> = []
    var quarantined: [String: Data] = [:]
    var initialMergeDone = false
    var localReplica: SettingsSyncReplica?
    /// Known to exist on the server; avoids a zone save with every edit.
    var zoneReady: Bool?
}
private struct SettingsSyncDisk: Codable {
    var schema = 1
    var enabled = false
    var account: String?
    var awaitingAccount = false
    var replica = SettingsSyncReplica()
    var observed: SettingsSyncProjection?
    var accounts: [String: CloudAccountState] = [:]
}

@MainActor
final class SettingsSyncCoordinator {
    private static let containerID = "iCloud.dev.cola16.TileLauncher"
    let status: SettingsSyncStatus
    private let settings: SettingsStore
    private let file: URL
    private var disk = SettingsSyncDisk()
    private var writable = true
    private var applying = false
    private var transport: SettingsCloudTransport?
    private var work: Task<Void, Never>?
    private var fetchDeadline: Task<Void, Never>?
    private var generation = UUID()
    private var accountObserver: NSObjectProtocol?
    private var iconBases: [UUID: [String: UInt64]] = [:]
    private var menuChecks: Set<String> = []
    private var manualRequest: UUID?
    private var zoneFetchFailed = false
    private var zoneFetchSucceeded = false
    /// Records rejected for a non-transient reason are not re-queued until the
    /// next explicit refresh, so a permanent error cannot become a send loop.
    private var rejected: Set<String> = []

    init(settings: SettingsStore, file: URL? = nil) {
        self.settings = settings; status = settings.syncStatus
        self.file = file ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TileLauncher/CloudSync/state.json")
        if FileManager.default.fileExists(atPath: self.file.path) {
            do {
                disk = try JSONDecoder().decode(SettingsSyncDisk.self, from: Data(contentsOf: self.file))
                guard disk.schema == 1 else { throw CocoaError(.coderReadCorrupt) }
            } catch {
                writable = false; status.error = "동기화 저장 파일을 읽지 못했습니다. 기존 파일을 보존했습니다."
            }
        }
        if disk.observed == nil {
            disk.replica.capture(before: nil, after: settings.syncProjection, at: Date())
            disk.observed = settings.syncProjection
        } else {
            // The journal is committed before UserDefaults, so replay a write
            // interrupted between the two stores without inventing edit times.
            applyReplica()
        }
        settings.onPersistentChange = { [weak self] in self?.capture() }
        status.enabled = disk.enabled; status.awaitingAccount = disk.awaitingAccount
        status.setEnabled = { [weak self] value in Task { @MainActor in self?.setEnabled(value) } }
        status.refresh = { [weak self] in Task { @MainActor in self?.refresh() } }
        status.chooseInitial = { [weak self] local in Task { @MainActor in self?.finishInitial(preferLocal: local) } }
        status.chooseIcon = { [weak self] id, symbol in Task { @MainActor in self?.chooseIcon(id, symbol) } }
        status.beginIconEdit = { [weak self] id in
            guard let self, self.iconBases[id] == nil, let shared = self.disk.replica.localIDs[id],
                  let menu = self.disk.replica.snapshot.combinedMenus.first(where: { $0.id == shared }) else { return }
            self.iconBases[id] = menu.icon.observed
        }
        status.clearIconEdits = { [weak self] in self?.iconBases = [:] }
        status.checkMenus = { [weak self] appID in self?.checkMenus(appID: appID) }
        accountObserver = NotificationCenter.default.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshAccount() }
        }
        publish(); persist()
        if disk.enabled && !disk.awaitingAccount { refresh() }
    }
    func shutdown() {
        stopTransport()
        if let accountObserver { NotificationCenter.default.removeObserver(accountObserver) }
        accountObserver = nil
        settings.onPersistentChange = nil
    }
    private func capture() {
        guard !applying, writable else { return }
        let old = disk.replica.snapshot
        let projection = settings.syncProjection
        disk.replica.capture(before: disk.observed, after: projection, at: Date(), iconBases: iconBases)
        disk.observed = projection
        guard old != disk.replica.snapshot else { return }
        markChanged(from: old)
        persist(); publish(); queueDirty()
    }
    private func markChanged(from old: SettingsSyncSnapshot) {
        guard let account = disk.account else { return }
        let before = Dictionary(old.records.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        for record in disk.replica.snapshot.records where before[record.name] != record {
            disk.accounts[account, default: .init()].dirty.insert(record.name)
        }
    }
    private func persist() {
        guard writable else { return }
        if let account = disk.account { disk.accounts[account, default: .init()].localReplica = disk.replica }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(disk).write(to: file, options: .atomic)
        } catch {
            status.error = "동기화 변경사항을 저장하지 못했습니다. 이 Mac의 설정은 유지되며 전송을 중단합니다."
            writable = false
            stopTransport()
        }
    }
    private func publish() {
        let shared = Set(disk.replica.localIDs.keys)
        if settings.sharedMenus != shared { settings.sharedMenus = shared }
        status.iconConflicts = disk.replica.snapshot.combinedMenus.filter { $0.isPresent && $0.icon.needsChoice }
        status.awaitingAccount = disk.awaitingAccount
    }
    private func applyReplica() {
        applying = true
        let oldCommands = settings.commands
        let value = disk.replica.applying(to: settings.syncProjection)
        let retained = Set(value.commands.map(\.id))
        let canonical = disk.replica.snapshot.canonicalMenuIDs
        // A deletion from another Mac removes the shared menu only; this Mac's
        // collection exclusions are local settings and stay unchanged.
        for command in oldCommands where !retained.contains(command.id) {
            guard let shared = disk.replica.localIDs[command.id],
                  let menu = disk.replica.snapshot.combinedMenus.first(where: { $0.id == (canonical[shared] ?? shared) }) else { continue }
            var shadow = command; shadow.isPinned = menu.pinned.value; shadow.symbol = menu.icon.displayed
            status.deletedMenus[command.id] = shadow
        }
        disk.observed = value
        persist() // records and cursor are authoritative before UI/defaults
        settings.applySyncProjection(value)
        let oldIDs = Set(oldCommands.map(\.id))
        for command in value.commands where !oldIDs.contains(command.id) {
            settings.menuCapture.excludedMenus.subtract(MenuPathMatch.paths(command).map { .init(appID: command.appID, path: $0) })
            settings.onMenuAdded?(command)
        }
        applying = false
        publish()
    }
    func setEnabled(_ value: Bool) {
        guard writable else { return }
        disk.enabled = value; status.enabled = value; persist()
        if value { refresh() }
        else {
            stopTransport(); status.locked = false; status.initialConflicts = []
            status.message = "이 Mac의 동기화를 껐습니다. 이후 변경 시각은 보존합니다."
        }
    }
    private func stopTransport() {
        generation = UUID(); work?.cancel(); work = nil; manualRequest = nil; rejected = []
        fetchDeadline?.cancel(); fetchDeadline = nil
        let old = transport; transport = nil
        Task { await old?.stop() }
    }
    private static var configured: Bool {
        guard let task = SecTaskCreateFromSelf(nil),
              let containers = SecTaskCopyValueForEntitlement(task, "com.apple.developer.icloud-container-identifiers" as CFString, nil) as? [String],
              containers.contains(containerID),
              let services = SecTaskCopyValueForEntitlement(task, "com.apple.developer.icloud-services" as CFString, nil) as? [String],
              services.contains("CloudKit") else { return false }
        return true
    }
    /// `lock` is for the settings window's initial read. A background retry
    /// never locks controls the user may already be editing.
    func refresh(lock: Bool = true) {
        guard writable, disk.enabled, !disk.awaitingAccount else { return }
        guard Self.configured else {
            status.locked = false; status.error = "이 실행본에는 iCloud 서명 권한이 없습니다. 오프라인으로 편집할 수 있습니다."
            return
        }
        if !status.initialConflicts.isEmpty { return }
        if lock { rejected = [] }
        let revision = generation
        if lock {
            status.locked = true; status.error = nil; status.message = "iCloud의 최신 변경사항을 확인하고 있습니다…"
            fetchDeadline?.cancel()
            fetchDeadline = Task { [weak self] in
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled, let self, self.generation == revision else { return }
                self.status.locked = false
                self.status.error = "iCloud 응답을 기다리고 있습니다. 오프라인 편집을 허용하며 연결되면 다시 합칩니다."
            }
        }
        work?.cancel()
        let request = UUID(); manualRequest = request
        work = Task { [weak self] in
            guard let self else { return }
            defer { if self.manualRequest == request { self.manualRequest = nil } }
            do {
                let container = CKContainer(identifier: Self.containerID)
                let accountID = try await container.userRecordID().recordName
                guard !Task.isCancelled, self.generation == revision else { return }
                let key = Self.accountKey(accountID)
                if let old = self.disk.account, old != key {
                    self.accountChanged(); return
                }
                if self.disk.account == nil, self.disk.accounts[key] != nil {
                    // Joining (or returning to) an account after "합치기": run the
                    // initial merge again so records only this Mac has are uploaded.
                    if let previous = self.disk.accounts[key]?.localReplica {
                        self.disk.replica.snapshot = try previous.snapshot.merged(with: self.disk.replica.snapshot)
                    }
                    self.disk.accounts[key]!.initialMergeDone = false
                }
                self.disk.account = key
                if self.disk.accounts[key] == nil { self.disk.accounts[key] = .init() }
                if self.transport == nil {
                    let transport = SettingsCloudTransport(owner: self)
                    self.transport = transport
                    await transport.start(database: container.privateCloudDatabase, state: self.disk.accounts[key]?.engine)
                }
                guard let transport = self.transport else { return }
                try await transport.fetch()
                guard !Task.isCancelled, self.transport?.id == transport.id, self.generation == revision else { return }
                guard !self.zoneFetchFailed else { throw CocoaError(.fileReadUnknown) }
                self.fetchCompleted()
            } catch {
                guard !Task.isCancelled, self.generation == revision else { return }
                self.status.locked = false; self.fetchDeadline?.cancel()
                self.status.error = "iCloud 동기화에 실패했습니다. 오프라인으로 편집할 수 있습니다. \(error.localizedDescription)"
            }
        }
    }
    private static func accountKey(_ name: String) -> String {
        SHA256.hash(data: Data(name.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    private func refreshAccount() {
        guard disk.enabled, !disk.awaitingAccount, Self.configured else { return }
        Task { [weak self] in
            guard let self else { return }
            let id = try? await CKContainer(identifier: Self.containerID).userRecordID().recordName
            guard self.disk.enabled, !self.disk.awaitingAccount else { return }
            // Never connected (e.g. enabled while signed out): a first sign-in
            // is not an account change; connect without asking.
            guard let previous = self.disk.account else {
                if id != nil { self.refresh(lock: false) }
                return
            }
            if let id, previous == Self.accountKey(id) { return }
            self.accountChanged()
        }
    }
    private func accountChanged() {
        guard disk.enabled else { return }
        stopTransport(); disk.awaitingAccount = true; status.locked = false
        status.message = "iCloud 계정이 변경되었습니다. 다음 오버레이에서 동기화 방법을 선택해 주세요."
        persist(); publish()
    }
    /// Called before opening an overlay. Never upload into a different account
    /// merely because a remote account-change event arrived.
    func presentAccountChangeIfNeeded() -> Bool {
        guard disk.enabled, disk.awaitingAccount else { return false }
        let alert = NSAlert()
        alert.messageText = "iCloud 계정이 변경되었습니다."
        alert.informativeText = "현재 설정을 새 계정의 설정과 합치겠습니까? 이 Mac의 동기화를 끌 수도 있습니다."
        alert.addButton(withTitle: "합치기"); alert.addButton(withTitle: "동기화 끄기")
        if alert.runModal() == .alertFirstButtonReturn {
            disk.awaitingAccount = false; disk.account = nil
            // Previous-account deletion markers must not become deletions in
            // the new account. Visible data is preserved as the merge input.
            let visible = settings.syncProjection
            var fresh = disk.replica
            let menus = fresh.snapshot.combinedMenus.filter(\.isPresent)
            fresh.snapshot.menus = Dictionary(menus.map { menu in
                var value = menu
                value.presence.value = true
                return (value.id, value)
            }, uniquingKeysWith: { a, _ in a })
            let ids = Set(fresh.snapshot.menus.keys)
            for (appID, field) in fresh.snapshot.orders {
                fresh.snapshot.orders[appID] = .init(field.value.filter(ids.contains), stamp: field.stamp)
            }
            fresh.localIDs = fresh.localIDs.filter { ids.contains($0.value) }
            disk.replica = fresh; disk.observed = visible
            status.awaitingAccount = false; persist(); refresh()
        } else { setEnabled(false) }
        return true
    }
    private func fetchCompleted() {
        guard let key = disk.account else { return }
        fetchDeadline?.cancel()
        let account = disk.accounts[key, default: .init()]
        if !account.initialMergeDone {
            let conflicts = disk.replica.legacyConflicts(with: account.remote)
            if !conflicts.isEmpty {
                status.initialConflicts = conflicts; status.locked = true
                status.message = "2.0 이전 설정의 충돌을 선택해 주세요. 충돌 없는 항목은 합칩니다."
                persist(); return
            }
            finishInitial(preferLocal: nil)
        } else {
            do {
                let before = disk.replica.snapshot
                try disk.replica.mergeInitial(account.remote, preferLocal: nil, at: Date())
                markChanged(from: before)
                applyReplica(); status.locked = false
                if account.quarantined.isEmpty { status.error = nil }
                status.message = "iCloud의 최신 설정을 반영했습니다."
                queueDirty()
            } catch { status.locked = false; status.error = "동기화 기록 병합을 완료하지 못했습니다." }
        }
    }
    private func finishInitial(preferLocal: Bool?) {
        guard let key = disk.account else { return }
        do {
            try disk.replica.mergeInitial(disk.accounts[key, default: .init()].remote, preferLocal: preferLocal, at: Date())
            disk.accounts[key]!.initialMergeDone = true
            disk.accounts[key]!.dirty.formUnion(disk.replica.snapshot.records.map(\.name))
            status.initialConflicts = []; status.locked = false
            if disk.accounts[key]!.quarantined.isEmpty { status.error = nil }
            applyReplica(); status.message = "iCloud 동기화가 켜져 있습니다."
            queueDirty()
        } catch { status.locked = false; status.error = "초기 동기화를 완료하지 못했습니다. 기존 데이터는 보존했습니다." }
    }
    private func queueDirty() {
        guard writable, disk.enabled, !disk.awaitingAccount, let key = disk.account,
              let account = disk.accounts[key], account.initialMergeDone, let transport else { return }
        let names = account.dirty.filter { account.quarantined[$0] == nil && !rejected.contains($0) }
        guard !names.isEmpty else { return }
        let createZone = account.zoneReady != true
        Task { await transport.enqueue(Array(names), createZone: createZone) }
    }
    private func chooseIcon(_ id: String, _ symbol: String?) {
        let old = disk.replica.snapshot
        disk.replica.chooseIcon(menuID: id, symbol: symbol, at: Date())
        markChanged(from: old); applyReplica(); queueDirty()
    }
    func handle(_ event: CKSyncEngine.Event, transport: SettingsCloudTransport) async {
        guard self.transport?.id == transport.id, !disk.awaitingAccount, let key = disk.account else { return }
        switch event {
        case .stateUpdate(let update):
            disk.accounts[key]!.engine = update.stateSerialization; persist(); return
        case .accountChange(let event):
            switch event.changeType {
            case .signIn(let user): if Self.accountKey(user.recordName) != key { accountChanged(); return }
            case .signOut, .switchAccounts: accountChanged(); return
            @unknown default: accountChanged(); return
            }
        case .fetchedRecordZoneChanges(let changes):
            for change in changes.modifications { receive(change.record, account: key) }
            for deletion in changes.deletions where deletion.recordID.zoneID == SettingsCloudTransport.zone {
                let name = deletion.recordID.recordName
                disk.accounts[key]!.serverRecords.removeValue(forKey: name)
                disk.accounts[key]!.dirty.insert(name)
            }
        case .fetchedDatabaseChanges(let changes):
            if changes.deletions.contains(where: { $0.zoneID == SettingsCloudTransport.zone }) {
                disk.accounts[key]!.serverRecords = [:]
                disk.accounts[key]!.initialMergeDone = false
                disk.accounts[key]!.zoneReady = false
                await transport.enqueue([], createZone: true)
            }
        case .sentDatabaseChanges(let changes):
            if changes.savedZones.contains(where: { $0.zoneID == SettingsCloudTransport.zone }) {
                disk.accounts[key]!.zoneReady = true
            }
            if changes.failedZoneSaves.contains(where: { $0.zone.zoneID == SettingsCloudTransport.zone }) {
                status.error = "iCloud 저장 공간을 준비하지 못했습니다. 변경사항은 이 Mac에 보존합니다."
            }
        case .sentRecordZoneChanges(let changes):
            for record in changes.savedRecords {
                storeServer(record, account: key)
                if let value = decode(record), outgoingPayloads()[record.recordID.recordName] == value {
                    disk.accounts[key]!.dirty.remove(record.recordID.recordName)
                }
            }
            for failure in changes.failedRecordSaves {
                let name = failure.record.recordID.recordName
                switch failure.error.code {
                case .serverRecordChanged:
                    // Merge, then resend only if the merged value still differs.
                    if let record = failure.error.serverRecord {
                        receive(record, account: key)
                        if disk.accounts[key]!.quarantined[name] == nil, decode(record) != outgoingPayloads()[name] {
                            disk.accounts[key]!.dirty.insert(name)
                        }
                    } else { disk.accounts[key]!.dirty.insert(name) }
                case .zoneNotFound:
                    disk.accounts[key]!.zoneReady = false
                    disk.accounts[key]!.serverRecords.removeValue(forKey: name)
                    disk.accounts[key]!.dirty.insert(name)
                case .unknownItem:
                    disk.accounts[key]!.serverRecords.removeValue(forKey: name)
                    disk.accounts[key]!.dirty.insert(name)
                case .networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable, .notAuthenticated, .requestRateLimited, .accountTemporarilyUnavailable, .operationCancelled: break
                case .quotaExceeded:
                    rejected.insert(name)
                    status.error = "iCloud 저장 공간이 부족해 전송하지 못했습니다. 변경사항은 이 Mac에 보존합니다."
                default:
                    rejected.insert(name)
                    status.error = "iCloud 전송을 완료하지 못했습니다. 변경사항은 이 Mac에 보존합니다."
                }
            }
            if disk.accounts[key]!.initialMergeDone { applyReplica() }
            queueDirty()
        case .willFetchChanges:
            zoneFetchFailed = false; zoneFetchSucceeded = false
        case .didFetchRecordZoneChanges(let result):
            if result.zoneID == SettingsCloudTransport.zone {
                // A zone that does not exist (yet) is an empty, successful read.
                if let error = result.error, error.code != .zoneNotFound, error.code != .userDeletedZone {
                    zoneFetchFailed = true
                } else {
                    zoneFetchSucceeded = true
                    disk.accounts[key]!.zoneReady = result.error == nil
                }
            }
        case .didFetchChanges:
            // didFetchChanges itself has no success/error property. Never use
            // it alone as proof that the initial cloud read succeeded.
            if manualRequest == nil, !zoneFetchFailed {
                if zoneFetchSucceeded { fetchCompleted() }
                else if !disk.accounts[key]!.initialMergeDone { refresh(lock: false) }
            }
        default: break
        }
        persist()
    }
    private func receive(_ record: CKRecord, account: String) {
        guard record.recordID.zoneID == SettingsCloudTransport.zone else { return }
        storeServer(record, account: account)
        do {
            guard record.recordType == "TileSettings", let data = record["payload"] as? Data else { throw CocoaError(.coderReadCorrupt) }
            let payload = try SettingsSyncRecord.decodeVerified(data)
            guard payload.name == record.recordID.recordName else { throw CocoaError(.coderReadCorrupt) }
            try disk.accounts[account]!.remote.merge(record: payload)
            disk.accounts[account]!.quarantined.removeValue(forKey: record.recordID.recordName)
            if disk.accounts[account]!.initialMergeDone {
                let old = disk.replica.snapshot
                try disk.replica.snapshot.merge(record: payload)
                markChanged(from: old)
                if outgoingPayloads()[record.recordID.recordName] == payload {
                    disk.accounts[account]!.dirty.remove(record.recordID.recordName)
                }
            }
        } catch {
            disk.accounts[account]!.quarantined[record.recordID.recordName] = record["payload"] as? Data ?? Data()
            status.error = "일부 동기화 기록을 읽지 못해 보존했습니다. 나머지 기록은 계속 처리합니다."
        }
    }
    private func storeServer(_ record: CKRecord, account: String) {
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: record, requiringSecureCoding: true) {
            disk.accounts[account]!.serverRecords[record.recordID.recordName] = data
        }
    }
    private func decode(_ record: CKRecord) -> SettingsSyncRecord? {
        (record["payload"] as? Data).flatMap { try? JSONDecoder().decode(SettingsSyncRecord.self, from: $0) }
    }
    private func outgoingPayloads() -> [String: SettingsSyncRecord] {
        Dictionary(disk.replica.snapshot.records.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
    }
    func outgoingRecords(session: UUID) -> [String: CKRecord] {
        guard writable, disk.enabled, !disk.awaitingAccount, transport?.id == session,
              let key = disk.account, let account = disk.accounts[key], account.initialMergeDone else { return [:] }
        var result: [String: CKRecord] = [:]
        for (name, value) in outgoingPayloads() where account.dirty.contains(name) && account.quarantined[name] == nil && !rejected.contains(name) {
            let previous = account.serverRecords[name].flatMap { try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKRecord.self, from: $0) }
            let record = previous ?? CKRecord(recordType: "TileSettings", recordID: .init(recordName: name, zoneID: SettingsCloudTransport.zone))
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            if let data = try? encoder.encode(value), data.count < 900_000 {
                record["payload"] = data as CKRecordValue; result[name] = record
            } else { status.error = "동기화 기록의 크기가 너무 커 전송하지 못했습니다." }
        }
        return result
    }
    private func checkMenus(appID: String) {
        guard !menuChecks.contains(appID) else { return }
        let commands = settings.commands.filter { $0.appID == appID }
        menuChecks.insert(appID)
        Task { [weak self] in
            let missing = await MenuAvailabilityReader.missing(commands)
            guard let self else { return }
            self.menuChecks.remove(appID)
            self.settings.unavailableMenus.subtract(commands.map(\.id))
            self.settings.unavailableMenus.formUnion(missing)
        }
    }
}
