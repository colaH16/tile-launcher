import DeckCore
import Foundation

extension SettingsStore {
    var syncProjection: SettingsSyncProjection {
        .init(preferences: [
            "reopenEnabled": .bool(optionReopen.enabled), "reopenInterval": .seconds(optionReopen.interval),
            "numberShortcuts": .text(numberShortcuts.rawValue), "automaticWindowCount": .bool(automatic),
            "manualWindowCount": .integer(manualCount), "theme": .text(theme.rawValue),
            "menuColor": .color(tileColors.menus?.hex), "windowColor": .color(tileColors.windows?.hex),
            "handoffColor": .color(tileColors.handoff?.hex), "registeredColor": .color(tileColors.registered?.hex),
            "showAppSettings": .bool(showAppSettingsTile)
        ], commands: commands)
    }
    /// Assigns only values that differ: every assignment triggers a full
    /// UserDefaults save, so an unchanged apply must write nothing.
    func applySyncProjection(_ projection: SettingsSyncProjection) {
        batchSave {
            func set<T: Equatable>(_ path: ReferenceWritableKeyPath<SettingsStore, T>, _ value: T) {
                if self[keyPath: path] != value { self[keyPath: path] = value }
            }
            for (key, value) in projection.preferences {
                guard let name = SettingsSyncPreference(rawValue: key), name.accepts(value) else { continue }
                switch (name, value) {
                case (.reopenEnabled, .bool(let flag)): set(\.optionReopen, .init(enabled: flag, interval: optionReopen.interval))
                case (.reopenInterval, .seconds(let value)): set(\.optionReopen, .init(enabled: optionReopen.enabled, interval: value))
                case (.numberShortcuts, .text(let value)): if let value = NumberShortcutAssignment(rawValue: value) { set(\.numberShortcuts, value) }
                case (.automaticWindowCount, .bool(let value)): set(\.automatic, value)
                case (.manualWindowCount, .integer(let value)): set(\.manualCount, value)
                case (.theme, .text(let value)): if let value = DeckTheme(rawValue: value) { set(\.theme, value) }
                case (.showAppSettings, .bool(let value)): set(\.showAppSettingsTile, value)
                case (.menuColor, .color(let value)): set(\.tileColors.menus, value.map(TileColor.init))
                case (.windowColor, .color(let value)): set(\.tileColors.windows, value.map(TileColor.init))
                case (.handoffColor, .color(let value)): set(\.tileColors.handoff, value.map(TileColor.init))
                case (.registeredColor, .color(let value)): set(\.tileColors.registered, value.map(TileColor.init))
                default: break
                }
            }
            if commands != projection.commands { commands = projection.commands }
        }
    }
}
