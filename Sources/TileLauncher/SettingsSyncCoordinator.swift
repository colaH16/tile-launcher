import AppKit
import CloudKit
import CryptoKit
import DeckCore
import Network
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
    /// Nonce of the last journaled change; copied to UserDefaults after its keys are written.
    var commit: String?
    var accounts: [String: CloudAccountState] = [:]
}

@MainActor
final class SettingsSyncCoordinator {
    private static let containerID = "iCloud.dev.cola16.TileLauncher"
    private static let checkpointKey = "settingsSyncCheckpoint"
    let status: SettingsSyncStatus
    private let settings: SettingsStore
    private let defaults: UserDefaults
    private let file: URL
    private let write: (Data, URL) throws -> Void
    private var disk = SettingsSyncDisk()
    /// An unreadable journal is preserved: never written, never applied.
    private var readOnly = false
    /// The last journal write failed: edits are kept in memory, the network
    /// stops, and the next change retries the write.
    private var writeFailed = false
    private var applying = false
    private var lastApplied: SettingsSyncSnapshot?
    private var accountCheck = 0
    private var retry: Task<Void, Never>?
    private var retryDelay = Duration.seconds(30)
    private var path: NWPathMonitor?
    private var online = true
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
    /// Locks follow the agreed scope: only while the settings window is
    /// visible, until its initial read finishes or a pending first-merge
    /// choice is made. Upload gating is independent (`initialMergeDone`).
    private var settingsVisible = false
    private var lockedRead = false

    /// `defaults` must be the store's UserDefaults; `write` is replaced only by
    /// isolated validation to simulate a failing disk.
    init(settings: SettingsStore, defaults: UserDefaults = .standard, file: URL? = nil,
         write: @escaping (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }) {
        self.settings = settings; self.defaults = defaults; self.write = write; status = settings.syncStatus
        self.file = file ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TileLauncher/CloudSync/state.json")
        if FileManager.default.fileExists(atPath: self.file.path) {
            do {
                // Validate a local candidate first: a future or partial journal
                // must never reach `disk`, where it could rewrite defaults.
                let candidate = try JSONDecoder().decode(SettingsSyncDisk.self, from: Data(contentsOf: self.file))
                guard candidate.schema == 1 else { throw CocoaError(.coderReadCorrupt) }
                guard !candidate.replica.device.isEmpty else { throw CocoaError(.coderReadCorrupt) }
                try candidate.replica.snapshot.validate()
                for account in candidate.accounts.values {
                    try account.remote.validate()
                    if let replica = account.localReplica {
                        guard !replica.device.isEmpty else { throw CocoaError(.coderReadCorrupt) }
                        try replica.snapshot.validate()
                    }
                }
                disk = candidate
            } catch {
                readOnly = true; status.error = "동기화 저장 파일을 읽지 못했습니다. 기존 파일을 보존했습니다."
            }
        }
        if let observed = disk.observed {
            let current = settings.syncProjection
            let startup = SettingsSyncLifecycle.startup(current: current, observed: observed, journalCommit: disk.commit,
                                                        defaultsCheckpoint: defaults.string(forKey: Self.checkpointKey),
                                                        managed: Set(disk.replica.localIDs.keys))
            if startup == .externalEdit {
                // Keep changes made outside the journal, without an edit time.
                let old = disk.replica.snapshot
                disk.replica.importExternal(before: observed, after: current)
                disk.observed = current
                markChanged(from: old)
            }
            // Replays an interrupted defaults write, and applies merged remote
            // records that were journaled but not yet shown.
            applyReplica()
        } else {
            disk.replica.capture(before: nil, after: settings.syncProjection, at: Date())
            disk.observed = settings.syncProjection
        }
        if !readOnly {
            let previous = disk.replica.snapshot
            disk.replica.seedExecutionSelections(from: disk.observed ?? settings.syncProjection)
            markChanged(from: previous)
        }
        settings.onPersistentChange = { [weak self] in self?.capture() }
        settings.onPersistentWrite = { [weak self] in self?.checkpoint() }
        status.enabled = disk.enabled; status.awaitingAccount = disk.awaitingAccount
        status.setEnabled = { [weak self] value in Task { @MainActor in self?.setEnabled(value) } }
        status.refresh = { [weak self] in Task { @MainActor in self?.refresh() } }
        status.setSettingsVisible = { [weak self] visible in
            guard let self else { return }
            self.settingsVisible = visible; self.updateLock()
        }
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
        // Network recovery retries only a connection that never started; a
        // running engine schedules its own work.
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            Task { @MainActor in self?.networkChanged(satisfied) }
        }
        monitor.start(queue: .main)
        path = monitor
        publish(); persist()
        // Launch never locks; only the settings window's read does.
        if disk.enabled && !disk.awaitingAccount { refresh(lock: false) }
    }
    func shutdown() {
        stopTransport()
        path?.cancel(); path = nil
        if let accountObserver { NotificationCenter.default.removeObserver(accountObserver) }
        accountObserver = nil
        settings.onPersistentChange = nil
        settings.onPersistentWrite = nil
    }
    private func capture() {
        guard !applying, !readOnly else { return }
        let old = disk.replica.snapshot
        let projection = settings.syncProjection
        disk.replica.capture(before: disk.observed, after: projection, at: Date(), iconBases: iconBases)
        disk.observed = projection
        guard old != disk.replica.snapshot else { return }
        markChanged(from: old)
        // The store's completion hook checkpoints this commit synchronously
        // after all defaults keys, without a queued callback surviving shutdown.
        _ = commit()
        publish(); queueDirty()
    }
    /// Journals a change that UserDefaults will receive next. Returns whether
    /// the journal write succeeded, i.e. whether the checkpoint may follow.
    private func commit() -> Bool {
        // A nonce only becomes current once it is on disk. Otherwise a later
        // non-commit persist would write it without its checkpoint, and an
        // older version's edit would look like an interrupted write.
        let previous = disk.commit
        disk.commit = UUID().uuidString
        if persist() { return true }
        disk.commit = previous
        return false
    }
    private func updateLock() {
        let value = settingsVisible && (lockedRead || !status.initialConflicts.isEmpty)
        if status.locked != value { status.locked = value }
    }
    private func checkpoint() {
        guard !readOnly, !writeFailed, let commit = disk.commit else { return }
        guard defaults.string(forKey: Self.checkpointKey) != commit else { return }
        defaults.set(commit, forKey: Self.checkpointKey)
    }
    private func markChanged(from old: SettingsSyncSnapshot) {
        guard let account = disk.account else { return }
        let before = Dictionary(old.records.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        for record in disk.replica.snapshot.records where before[record.name] != record {
            disk.accounts[account, default: .init()].dirty.insert(record.name)
        }
    }
    @discardableResult private func persist() -> Bool {
        guard !readOnly else { return false }
        if let account = disk.account { disk.accounts[account, default: .init()].localReplica = disk.replica }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            try write(encoder.encode(disk), file)
            if writeFailed {
                writeFailed = false; status.error = nil
                if disk.enabled && !disk.awaitingAccount { refresh(lock: false) }
            }
            return true
        } catch {
            if !writeFailed {
                writeFailed = true
                status.error = "동기화 변경사항을 저장하지 못했습니다. 이 Mac의 설정은 유지되며, 다시 저장될 때까지 전송을 멈춥니다."
                stopTransport()
            }
            return false
        }
    }
    private func publish() {
        let shared = Set(disk.replica.localIDs.keys)
        if settings.sharedMenus != shared { settings.sharedMenus = shared }
        status.iconConflicts = disk.replica.snapshot.combinedMenus.filter { $0.isPresent && $0.icon.needsChoice }
        status.awaitingAccount = disk.awaitingAccount
    }
    /// Skips work when nothing changed since the last apply (e.g. a send echo).
    private func applyReplicaIfNeeded() {
        if disk.replica.snapshot != lastApplied { applyReplica() }
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
        let committed = commit() // records and cursor are authoritative before UI/defaults
        settings.applySyncProjection(value)
        if committed { checkpoint() }
        lastApplied = disk.replica.snapshot
        let oldIDs = Set(oldCommands.map(\.id))
        for command in value.commands where !oldIDs.contains(command.id) {
            settings.menuCapture.excludedMenus.subtract(MenuPathMatch.paths(command).map { .init(appID: command.appID, path: $0) })
            settings.onMenuAdded?(command)
        }
        applying = false
        publish()
    }
    func setEnabled(_ value: Bool) {
        guard !readOnly else { return }
        disk.enabled = value; status.enabled = value; persist()
        if value { refresh() }
        else {
            stopTransport(); status.initialConflicts = []; updateLock()
            status.message = "이 Mac의 동기화를 껐습니다. 이후 변경 시각은 보존합니다."
        }
    }
    private func stopTransport() {
        generation = UUID(); work?.cancel(); work = nil; manualRequest = nil; rejected = []
        fetchDeadline?.cancel(); fetchDeadline = nil
        retry?.cancel(); retry = nil
        lockedRead = false; updateLock()
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
        guard !readOnly, !writeFailed, disk.enabled, !disk.awaitingAccount else { return }
        guard Self.configured else {
            lockedRead = false; updateLock()
            status.error = "이 실행본에는 iCloud 서명 권한이 없습니다. 오프라인으로 편집할 수 있습니다."
            return
        }
        if !status.initialConflicts.isEmpty { return }
        if lock { rejected = [] }
        let revision = generation
        if lock {
            lockedRead = true; updateLock(); status.error = nil; status.message = "iCloud의 최신 변경사항을 확인하고 있습니다…"
            fetchDeadline?.cancel()
            fetchDeadline = Task { [weak self] in
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled, let self, self.generation == revision else { return }
                self.lockedRead = false; self.updateLock()
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
                self.retryDelay = .seconds(30)
                self.fetchCompleted()
            } catch {
                guard !Task.isCancelled, self.generation == revision else { return }
                self.lockedRead = false; self.updateLock(); self.fetchDeadline?.cancel()
                self.status.error = "iCloud 동기화에 실패했습니다. 오프라인으로 편집할 수 있습니다. \(error.localizedDescription)"
                // Without an engine nothing else would retry (e.g. launched offline).
                if self.transport == nil { self.scheduleRetry() }
            }
        }
    }
    private static func accountKey(_ name: String) -> String {
        SHA256.hash(data: Data(name.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    /// Bounded backoff (30 s doubling to 15 min) while no engine exists.
    private func scheduleRetry() {
        guard retry == nil, transport == nil, disk.enabled, !disk.awaitingAccount, !readOnly else { return }
        let delay = retryDelay, revision = generation
        retryDelay = min(retryDelay * 2, .seconds(900))
        retry = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, self.generation == revision else { return }
            self.retry = nil
            if self.transport == nil { self.refresh(lock: false) }
        }
    }
    private func networkChanged(_ satisfied: Bool) {
        defer { online = satisfied }
        guard satisfied, !online, transport == nil, disk.enabled, !disk.awaitingAccount else { return }
        retry?.cancel(); retry = nil
        refresh(lock: false)
    }
    private func refreshAccount() {
        guard disk.enabled, !disk.awaitingAccount, !readOnly, Self.configured else { return }
        accountCheck += 1
        let check = accountCheck, revision = generation
        Task { [weak self] in
            let container = CKContainer(identifier: Self.containerID)
            let status: SettingsSyncLifecycle.AccountStatus
            switch try? await container.accountStatus() {
            case .available?:
                status = .available((try? await container.userRecordID().recordName).map(Self.accountKey))
            case .noAccount?: status = .noAccount
            case .restricted?: status = .restricted
            case .temporarilyUnavailable?: status = .temporarilyUnavailable
            default: status = .couldNotDetermine
            }
            // Only the newest check of the current session may act.
            guard let self, self.accountCheck == check, self.generation == revision,
                  self.disk.enabled, !self.disk.awaitingAccount else { return }
            switch SettingsSyncLifecycle.accountDecision(previous: self.disk.account, status: status) {
            case .changed: self.accountChanged()
            case .connect: if self.transport == nil { self.refresh(lock: false) }
            case .none: break
            }
        }
    }
    private func accountChanged() {
        guard disk.enabled else { return }
        stopTransport(); disk.awaitingAccount = true
        // Choices for the previous account's first merge no longer apply.
        status.initialConflicts = []; updateLock()
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
                // Waiting for the choice keeps uploads gated; edits lock only
                // while the settings window shows the choice.
                status.initialConflicts = conflicts; lockedRead = false; updateLock()
                status.message = "2.0 이전 설정의 충돌을 선택해 주세요. 충돌 없는 항목은 합칩니다."
                persist(); return
            }
            finishInitial(preferLocal: nil)
        } else {
            do {
                let before = disk.replica.snapshot
                try disk.replica.mergeInitial(account.remote, preferLocal: nil, at: Date())
                markChanged(from: before)
                applyReplicaIfNeeded(); lockedRead = false; updateLock()
                if account.quarantined.isEmpty { status.error = nil }
                status.message = "iCloud의 최신 설정을 반영했습니다."
                queueDirty()
            } catch { lockedRead = false; updateLock(); status.error = "동기화 기록 병합을 완료하지 못했습니다." }
        }
    }
    private func finishInitial(preferLocal: Bool?) {
        guard let key = disk.account else { return }
        do {
            try disk.replica.mergeInitial(disk.accounts[key, default: .init()].remote, preferLocal: preferLocal, at: Date())
            disk.accounts[key]!.initialMergeDone = true
            // Upload what the account lacks or holds differently; identical
            // records already on the server are not re-sent to every Mac.
            let remote = disk.accounts[key]!.remote
            disk.accounts[key]!.dirty.formUnion(disk.replica.snapshot.records.filter { remote.record(named: $0.name) != $0 }.map(\.name))
            status.initialConflicts = []; lockedRead = false; updateLock()
            if disk.accounts[key]!.quarantined.isEmpty { status.error = nil }
            applyReplica(); status.message = "iCloud 동기화가 켜져 있습니다."
            queueDirty()
        } catch { lockedRead = false; updateLock(); status.error = "초기 동기화를 완료하지 못했습니다. 기존 데이터는 보존했습니다." }
    }
    private func queueDirty() {
        guard !readOnly, !writeFailed, disk.enabled, !disk.awaitingAccount, let key = disk.account,
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
                recordDeleted(deletion.recordID.recordName, account: key)
            }
        case .fetchedDatabaseChanges(let changes):
            for deletion in changes.deletions where deletion.zoneID == SettingsCloudTransport.zone {
                let reason: SettingsSyncLifecycle.ZoneDeletion
                switch deletion.reason {
                case .deleted: reason = .deletedByApp
                case .purged: reason = .purgedByUser
                case .encryptedDataReset: reason = .encryptedDataReset
                @unknown default: reason = .unknown
                }
                guard SettingsSyncLifecycle.action(for: reason) == .recreate else { iCloudDataRemoved(account: key); return }
                // Deleted by this app (another Mac): the server is empty, so
                // nothing cached for that zone may hold back the re-creation.
                disk.accounts[key]!.serverRecords = [:]
                disk.accounts[key]!.remote = SettingsSyncSnapshot()
                disk.accounts[key]!.quarantined = [:]
                disk.accounts[key]!.initialMergeDone = false
                disk.accounts[key]!.zoneReady = false
                await transport.enqueue([], createZone: true)
            }
        case .sentDatabaseChanges(let changes):
            if changes.savedZones.contains(where: { $0.zoneID == SettingsCloudTransport.zone }) {
                disk.accounts[key]!.zoneReady = true
            }
            if let failure = changes.failedZoneSaves.first(where: { $0.zone.zoneID == SettingsCloudTransport.zone }) {
                if failure.error.code == .userDeletedZone { iCloudDataRemoved(account: key); return }
                status.error = "iCloud 저장 공간을 준비하지 못했습니다. 변경사항은 이 Mac에 보존합니다."
            }
        case .sentRecordZoneChanges(let changes):
            if changes.failedRecordSaves.contains(where: { $0.error.code == .userDeletedZone }) {
                iCloudDataRemoved(account: key); return
            }
            // Saved acknowledgements only change server metadata and dirty flags.
            for record in changes.savedRecords {
                storeServer(record, account: key)
                if let value = decode(record), disk.replica.snapshot.record(named: record.recordID.recordName) == value {
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
                        if disk.accounts[key]!.quarantined[name] == nil, decode(record) != disk.replica.snapshot.record(named: name) {
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
            if disk.accounts[key]!.initialMergeDone { applyReplicaIfNeeded() }
            queueDirty()
        case .willFetchChanges:
            zoneFetchFailed = false; zoneFetchSucceeded = false
        case .didFetchRecordZoneChanges(let result):
            if result.zoneID == SettingsCloudTransport.zone {
                // The user deleted the data in Settings: never resend it.
                if result.error?.code == .userDeletedZone { iCloudDataRemoved(account: key); return }
                // A zone that does not exist yet (first connection) is an empty read.
                if let error = result.error, error.code != .zoneNotFound {
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
    /// `purged` / `encryptedDataReset` / `userDeletedZone`: Apple requires
    /// deleting locally cached data and not resending it. This Mac's own
    /// settings (UserDefaults) stay; the account's cached records, outbox,
    /// cursor and quarantine are dropped, the journal restarts from the current
    /// settings as legacy values (no new edit time), and this Mac stops
    /// syncing until the user turns it on again.
    private func iCloudDataRemoved(account key: String) {
        stopTransport()
        disk.accounts[key] = CloudAccountState()
        var fresh = SettingsSyncReplica()
        let current = settings.syncProjection
        fresh.capture(before: nil, after: current, at: Date())
        disk.replica = fresh; disk.observed = current; lastApplied = nil
        disk.enabled = false; disk.awaitingAccount = false
        status.enabled = false; status.initialConflicts = []; status.deletedMenus = [:]; updateLock()
        status.message = "이 Mac의 동기화를 껐습니다."
        status.error = "iCloud에서 Tile Launcher 동기화 데이터가 삭제되었습니다(설정 앱의 데이터 삭제 또는 암호화 데이터 재설정). 이 Mac의 설정은 그대로 두었고, 삭제된 데이터를 다시 올리지 않도록 동기화를 껐습니다."
        persist(); publish()
    }
    private func receive(_ record: CKRecord, account: String) {
        guard record.recordID.zoneID == SettingsCloudTransport.zone else { return }
        storeServer(record, account: account)
        do {
            guard record.recordType == "TileSettings", let data = record["payload"] as? Data else { throw CocoaError(.coderReadCorrupt) }
            let payload = try SettingsSyncRecord.decodeVerified(data)
            guard payload.name == record.recordID.recordName else { throw CocoaError(.coderReadCorrupt) }
            if !disk.accounts[account]!.initialMergeDone, let incoming = payload.menu,
               let own = disk.replica.snapshot.menus[incoming.id],
               !SettingsSyncSnapshot.consistent([own, incoming]) {
                // The initial snapshot is staged before it is applied, but an
                // impossible shared identity must not poison that first merge.
                throw SettingsSyncSnapshot.MergeError.inconsistentIdentity
            }
            let stagedBefore = disk.accounts[account]!.remote.record(named: payload.name)
            try disk.accounts[account]!.remote.merge(record: payload)
            do {
                if disk.accounts[account]!.initialMergeDone {
                    // Compare only this record; keep the staged and live
                    // snapshots atomic even for a local identity conflict.
                    let name = payload.name
                    let before = disk.replica.snapshot.record(named: name)
                    try disk.replica.snapshot.merge(record: payload)
                    let after = disk.replica.snapshot.record(named: name)
                    if after == payload { disk.accounts[account]!.dirty.remove(name) }
                    else if after != before { disk.accounts[account]!.dirty.insert(name) }
                }
            } catch {
                restoreRemote(stagedBefore, replacing: payload, account: account)
                throw error
            }
            disk.accounts[account]!.quarantined.removeValue(forKey: record.recordID.recordName)
        } catch {
            disk.accounts[account]!.quarantined[record.recordID.recordName] = record["payload"] as? Data ?? Data()
            status.error = "일부 동기화 기록을 읽지 못해 보존했습니다. 나머지 기록은 계속 처리합니다."
        }
    }
    /// Restore only the affected entry, retaining constant-size rollback rather
    /// than copying a complete account snapshot for each incoming record.
    private func restoreRemote(_ previous: SettingsSyncRecord?, replacing record: SettingsSyncRecord, account: String) {
        if let menu = record.menu { disk.accounts[account]!.remote.menus[menu.id] = previous?.menu }
        else if let key = record.preference { disk.accounts[account]!.remote.preferences[key] = previous?.value }
        else if let key = record.appOrder { disk.accounts[account]!.remote.orders[key] = previous?.order }
    }
    private func recordDeleted(_ name: String, account: String) {
        disk.accounts[account]!.serverRecords.removeValue(forKey: name)
        disk.accounts[account]!.quarantined.removeValue(forKey: name)
        if let record = disk.accounts[account]!.remote.record(named: name) {
            restoreRemote(nil, replacing: record, account: account)
        }
        if disk.replica.snapshot.record(named: name) != nil { disk.accounts[account]!.dirty.insert(name) }
        else { disk.accounts[account]!.dirty.remove(name) }
    }
    private func storeServer(_ record: CKRecord, account: String) {
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: record, requiringSecureCoding: true) {
            disk.accounts[account]!.serverRecords[record.recordID.recordName] = data
        }
    }
    private func decode(_ record: CKRecord) -> SettingsSyncRecord? {
        (record["payload"] as? Data).flatMap { try? JSONDecoder().decode(SettingsSyncRecord.self, from: $0) }
    }
    func outgoingRecords(session: UUID) -> [String: CKRecord] {
        guard !readOnly, !writeFailed, disk.enabled, !disk.awaitingAccount, transport?.id == session,
              let key = disk.account, let account = disk.accounts[key], account.initialMergeDone else { return [:] }
        var result: [String: CKRecord] = [:]
        for name in account.dirty where account.quarantined[name] == nil && !rejected.contains(name) {
            guard let value = disk.replica.snapshot.record(named: name) else { continue }
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

#if TILE_LAUNCHER_DIAGNOSTICS
extension SettingsSyncCoordinator {
    /// Exercises the real coordinator with in-memory CKRecord values. The
    /// transport is never started: no CKContainer, engine or network is created.
    @MainActor static func verifyOfflineCoordinator(root: URL) throws {
        let suite = "TileLauncher.SyncValidation.coordinator." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        settings.theme = .classic
        settings.addCommand(.init(appID: "validation.app", appName: "Validation", path: ["File", "Local"]))
        let coordinator = SettingsSyncCoordinator(settings: settings, defaults: defaults,
                                                   file: root.appendingPathComponent("offline-coordinator.json"))
        defer { coordinator.shutdown() }
        coordinator.path?.cancel(); coordinator.path = nil
        if let observer = coordinator.accountObserver { NotificationCenter.default.removeObserver(observer) }
        coordinator.accountObserver = nil
        let account = "isolated-validation-account"
        coordinator.disk.account = account
        coordinator.disk.accounts[account] = .init()
        coordinator.disk.enabled = true
        let transport = SettingsCloudTransport(owner: coordinator)
        coordinator.transport = transport // no call to start()
        func check(_ condition: Bool, _ message: String) throws {
            if !condition { throw NSError(domain: "OfflineSyncCoordinator", code: 1,
                                           userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        func record(_ value: SettingsSyncRecord) throws -> CKRecord {
            let record = CKRecord(recordType: "TileSettings", recordID: .init(recordName: value.name, zoneID: SettingsCloudTransport.zone))
            record["payload"] = try JSONEncoder().encode(value) as CKRecordValue
            return record
        }
        let stamp = SettingsSyncStamp(date: nil, device: "validation-peer", sequence: 1)
        let remoteTheme = SettingsSyncRecord(preference: "theme", value: .init(.text("glass"), stamp: stamp))
        coordinator.receive(try record(remoteTheme), account: account)
        let remoteMenu = SettingsSyncMenu(id: "remote-menu", appID: "validation.app", appName: "Validation",
            path: ["File", "Remote"], presence: .init(true, stamp: stamp), pinned: .init(true, stamp: stamp),
            icon: .init([.init(symbol: "gear", stamp: stamp)]))
        coordinator.receive(try record(.init(menu: remoteMenu)), account: account)
        var future = SettingsSyncRecord(preference: "showAppSettings", value: .init(.bool(false), stamp: stamp))
        future.version = 99
        coordinator.receive(try record(future), account: account)
        try check(coordinator.disk.accounts[account]!.quarantined.count == 1, "Invalid record was not quarantined")
        try check(coordinator.disk.accounts[account]!.remote.menus.count == 1, "Invalid record blocked a valid peer record")
        let initialID = coordinator.disk.replica.localIDs[settings.commands[0].id]!
        let initialConflict = SettingsSyncMenu(id: initialID, appID: "different.validation.app", appName: "Different",
            path: ["File", "Different"], presence: .init(true, stamp: stamp), pinned: .init(true, stamp: stamp),
            icon: .init([.init(symbol: nil, stamp: stamp)]))
        coordinator.receive(try record(.init(menu: initialConflict)), account: account)
        try check(coordinator.disk.accounts[account]!.quarantined["menu-" + initialID] != nil
                  && coordinator.disk.accounts[account]!.remote.record(named: "menu-" + initialID) == nil,
                  "Conflicting identity poisoned the first staged merge")
        coordinator.recordDeleted("menu-" + initialID, account: account)
        coordinator.fetchCompleted()
        try check(coordinator.status.initialConflicts == ["pref:theme"], "Initial legacy choice was bypassed")
        try check(coordinator.outgoingRecords(session: transport.id).isEmpty, "Uploaded before the initial choice")
        // Lock scope: only while the settings window shows the pending choice.
        try check(!coordinator.status.locked, "A pending first-merge choice locked edits outside the settings window")
        let localID = settings.commands[0].id, wasPinned = settings.commands[0].isPinned
        settings.togglePin(localID)
        try check(settings.commands[0].isPinned != wasPinned, "Overlay edit was blocked while settings were closed")
        settings.togglePin(localID)
        coordinator.status.setSettingsVisible?(true)
        try check(coordinator.status.locked, "Reopened settings did not keep the pending choice locked")
        coordinator.status.setSettingsVisible?(false)
        try check(!coordinator.status.locked && coordinator.outgoingRecords(session: transport.id).isEmpty,
                  "Closing settings kept the lock or opened the upload gate")
        coordinator.finishInitial(preferLocal: false)
        try check(settings.theme == .glass && settings.commands.count == 2, "Initial choice did not preserve both menus")
        let outgoing = coordinator.outgoingRecords(session: transport.id)
        try check(!outgoing.isEmpty && outgoing[future.name] == nil, "Outbox omitted valid data or sent quarantine")
        try check(outgoing["menu-remote-menu"] == nil, "An unchanged record already in the account was queued again")
        // A newer peer value replaces the local one and clears its outbox entry.
        let newer = SettingsSyncStamp(date: Date().addingTimeInterval(60), device: "validation-peer", sequence: 2)
        coordinator.receive(try record(.init(preference: "theme", value: .init(.text("classic"), stamp: newer))), account: account)
        try check(!coordinator.disk.accounts[account]!.dirty.contains("pref-theme"), "Adopted peer value stayed in the outbox")
        try check(coordinator.disk.accounts[account]!.dirty.contains("menu-" + coordinator.disk.replica.localIDs[localID]!),
                  "A single-record receive cleared another record's outbox entry")
        // A valid peer record can still conflict with this Mac's identity.
        // It must not poison the staged snapshot and block unrelated records.
        let localShared = coordinator.disk.replica.localIDs[localID]!
        let conflicting = SettingsSyncMenu(id: localShared, appID: "different.validation.app", appName: "Different",
            path: ["File", "Different"], presence: .init(true, stamp: newer), pinned: .init(true, stamp: newer),
            icon: .init([.init(symbol: nil, stamp: newer)]))
        coordinator.receive(try record(.init(menu: conflicting)), account: account)
        try check(coordinator.disk.accounts[account]!.quarantined["menu-" + localShared] != nil,
                  "Conflicting peer identity was not quarantined")
        try check(coordinator.disk.accounts[account]!.remote.record(named: "menu-" + localShared) == nil,
                  "Rejected peer identity poisoned the staged snapshot")
        coordinator.fetchCompleted()
        try check(settings.theme == .classic, "One conflicting identity blocked an unrelated preference")
        coordinator.recordDeleted("menu-" + localShared, account: account)
        try check(coordinator.disk.accounts[account]!.quarantined["menu-" + localShared] == nil
                  && coordinator.disk.accounts[account]!.dirty.contains("menu-" + localShared),
                  "Deleted peer record left quarantine blocking valid local data")
        coordinator.recordDeleted("menu-remote-menu", account: account)
        try check(coordinator.disk.accounts[account]!.remote.menus["remote-menu"] == nil
                  && coordinator.disk.accounts[account]!.dirty.contains("menu-remote-menu"),
                  "Deleted server record stayed in the initial-merge comparison")
        coordinator.recordDeleted("unknown-without-local-data", account: account)
        try check(!coordinator.disk.accounts[account]!.dirty.contains("unknown-without-local-data"),
                  "Unknown deleted server record created a permanent empty outbox entry")
        try check(coordinator.outgoingRecords(session: UUID()).isEmpty, "An obsolete transport could obtain account records")
        coordinator.status.initialConflicts = ["pref:theme"]
        coordinator.accountChanged()
        try check(coordinator.disk.awaitingAccount && coordinator.status.initialConflicts.isEmpty,
                  "Account pause retained previous-account initial choices")
        try check(coordinator.outgoingRecords(session: transport.id).isEmpty, "Account change leaked the old outbox")
        let local = settings.syncProjection
        coordinator.iCloudDataRemoved(account: account)
        let cleaned = coordinator.disk.accounts[account]!
        try check(settings.syncProjection == local && !coordinator.disk.enabled, "Purge changed this Mac's settings or left sync running")
        try check(cleaned.engine == nil && cleaned.serverRecords.isEmpty && cleaned.remote == SettingsSyncSnapshot()
                  && cleaned.dirty.isEmpty && cleaned.quarantined.isEmpty, "Purge left server caches or pending uploads")
        try check(coordinator.outgoingRecords(session: transport.id).isEmpty, "Purge could resend old data")
        print("Offline coordinator: per-record quarantine, initial-choice upload gate, settings-only lock, single-record receive, account isolation and purge preservation passed without a CloudKit engine.")
    }
}
#endif
