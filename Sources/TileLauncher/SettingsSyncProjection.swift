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
    func applySyncProjection(_ projection: SettingsSyncProjection) {
        batchSave {
            for (key, value) in projection.preferences {
                guard let name = SettingsSyncPreference(rawValue: key), name.accepts(value) else { continue }
                switch (name, value) {
                case (.reopenEnabled, .bool(let flag)): optionReopen = .init(enabled: flag, interval: optionReopen.interval)
                case (.reopenInterval, .seconds(let value)): optionReopen = .init(enabled: optionReopen.enabled, interval: value)
                case (.numberShortcuts, .text(let value)): if let value = NumberShortcutAssignment(rawValue: value) { numberShortcuts = value }
                case (.automaticWindowCount, .bool(let value)): automatic = value
                case (.manualWindowCount, .integer(let value)): manualCount = value
                case (.theme, .text(let value)): if let value = DeckTheme(rawValue: value) { theme = value }
                case (.showAppSettings, .bool(let value)): showAppSettingsTile = value
                case (.menuColor, .color(let value)): tileColors.menus = value.map(TileColor.init)
                case (.windowColor, .color(let value)): tileColors.windows = value.map(TileColor.init)
                case (.handoffColor, .color(let value)): tileColors.handoff = value.map(TileColor.init)
                case (.registeredColor, .color(let value)): tileColors.registered = value.map(TileColor.init)
                default: break
                }
            }
            if commands != projection.commands { commands = projection.commands }
        }
    }
}
