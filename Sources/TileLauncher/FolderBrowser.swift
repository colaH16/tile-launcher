import AppKit
import SwiftUI

import DeckCore

final class FolderBrowser: ObservableObject {
    @Published var path: [URL] = []
    @Published var entries: [FolderEntry] = []
    @Published var loading = false
    @Published var error: String?
    @Published var sort: FolderSort = .added { didSet { sortEntries() } }
    @Published var rootName = ""
    var current: URL? { path.last }
    private let queue = DispatchQueue(label: "TileLauncher.folders", qos: .userInitiated)
    private var request = UUID()

    func open(_ pin: PinnedItem) {
        guard pin.opensInOverlay else { return }
        rootName = pin.name
        path = [pin.url]
        refresh()
    }
    func enter(_ entry: FolderEntry) { path.append(entry.url); refresh() }
    func back() {
        if path.count > 1 { path.removeLast(); refresh() }
        else { close() }
    }
    func close() { request = UUID(); path = []; entries = []; error = nil; loading = false }
    func refresh() {
        guard let url = current else { return }
        let token = UUID()
        request = token
        entries = []
        error = nil
        loading = true
        queue.async {
            do {
                let items = try FolderCatalog.read(url)
                DispatchQueue.main.async {
                    guard self.request == token else { return }
                    self.entries = items
                    self.sortEntries()
                    self.loading = false
                }
            } catch {
                DispatchQueue.main.async {
                    guard self.request == token else { return }
                    self.error = "폴더를 읽을 수 없습니다. 접근 권한을 확인하거나 Finder에서 열어 주세요."
                    self.loading = false
                }
            }
        }
    }
    private func sortEntries() {
        entries = FolderCatalog.sorted(entries, by: sort)
    }
}
