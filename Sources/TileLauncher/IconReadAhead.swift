import AppKit
import Combine
import DeckCore

/// Read immutable image objects ahead of display. Never rasterizes, scans app
/// resources or changes menu ordering. The normal display loaders remain intact.
final class IconReadAhead {
    private let queue = DispatchQueue(label: "TileLauncher.icon-read-ahead", qos: .utility)
    private weak var settings: SettingsStore?
    private let hasApp: (URL) -> Bool
    private let readApp: (URL) -> Void
    private let hasMenu: (MenuResourceIcon) -> Bool
    private let readMenu: (MenuResourceIcon) -> Void
    private var subscriptions: [AnyCancellable] = []
    private var pending: [String: DispatchWorkItem] = [:]
    private var stopped = false

    init(settings: SettingsStore,
         hasApp: @escaping (URL) -> Bool = { AppIconCache.shared.isCached($0) },
         readApp: @escaping (URL) -> Void = { _ = AppIconCache.shared.icon($0) },
         hasMenu: @escaping (MenuResourceIcon) -> Bool = { SavedMenuImages.isCached($0) },
         readMenu: @escaping (MenuResourceIcon) -> Void = { _ = SavedMenuImages.image($0) }) {
        self.settings = settings
        self.hasApp = hasApp; self.readApp = readApp
        self.hasMenu = hasMenu; self.readMenu = readMenu
        // Use the emitted values: @Published sends before properties are set.
        Publishers.CombineLatest4(settings.$profiles, settings.$manualProfileID,
                                  settings.$focusProfileID, settings.$followFocus)
            .map { profiles, manual, focus, follows -> [PinnedItem] in
                let selected = follows ? profiles.first(where: { $0.id == focus }) : nil
                return (selected ?? profiles.first(where: { $0.id == manual }) ?? profiles.first)?.items ?? []
            }
            .removeDuplicates()
            .sink { [weak self] in self?.prepareRegistered($0) }
            .store(in: &subscriptions)
        // Counts, last-used dates and pins don't change an image. New/manual/
        // automatic menus and late resource resolution do change this list.
        settings.$commands.map(Self.images).removeDuplicates().dropFirst()
            .sink { [weak self] in self?.prepareMenuImages($0) }
            .store(in: &subscriptions)
    }
    private static func images(_ commands: [MenuCommand]) -> [MenuResourceIcon] {
        commands.compactMap { $0.symbol == nil ? $0.resourceIcon : nil }
    }
    func activate(_ app: AppItem) {
        if let url = app.url { prepareApp(url) }
        prepareMenus(appID: app.id)
    }
    func prepareMenus(appID: String) {
        prepareMenuImages(Self.images(settings?.commands.filter { $0.appID == appID } ?? []))
    }
    func prepareApp(_ url: URL) {
        guard !hasApp(url) else { return }
        let hasApp = hasApp, readApp = readApp
        enqueue("app:" + url.path) { if !hasApp(url) { readApp(url) } }
    }
    func prepareRegistered(_ pins: [PinnedItem]) {
        // Bound speculative work to the existing image-cache capacity; a large
        // profile must not churn through icons it immediately evicts again.
        for pin in pins.prefix(96) {
            let hasApp = hasApp, readApp = readApp
            enqueue("app:" + pin.path) {
                let url = pin.url
                if !hasApp(url) { readApp(url) }
            }
        }
    }
    private func prepareMenuImages(_ images: [MenuResourceIcon]) {
        for icon in images.prefix(512) where icon.validDigest && !hasMenu(icon) {
            let hasMenu = hasMenu, readMenu = readMenu
            let key = "menu:" + icon.kind.rawValue + icon.digest + (icon.template ? ":template" : ":color")
            enqueue(key) { if !hasMenu(icon) { readMenu(icon) } }
        }
    }
    private func enqueue(_ key: String, read: @escaping () -> Void) {
        guard !stopped, pending[key] == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            autoreleasepool(invoking: read)
            DispatchQueue.main.async { [weak self] in self?.pending.removeValue(forKey: key) }
        }
        pending[key] = work
        queue.async(execute: work)
    }
    func stop() {
        stopped = true
        subscriptions.removeAll()
        for work in pending.values { work.cancel() }
        pending.removeAll()
    }
    deinit { for work in pending.values { work.cancel() } }
}
