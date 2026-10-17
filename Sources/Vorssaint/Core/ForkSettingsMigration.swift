// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint contributors

import Foundation

/// Copies compatible preferences from the official app on this Mac. Both apps
/// keep their own defaults domains, so either can continue running afterward.
enum ForkSettingsMigration {
    static let officialBundleID = "com.vorssaint.utils"
    static let forkBundleID = "com.imstevelin.vorssaint-imstevelin"
    private static let version = 1

    static func run() {
        // Diagnostic and uninstall commands must never change the user's live
        // preferences before they exit without starting the app.
        guard Bundle.main.bundleIdentifier == forkBundleID,
              !CommandLine.arguments.dropFirst().contains(where: { $0.hasPrefix("--") })
        else { return }
        _ = migrate(from: officialBundleID, to: forkBundleID, target: .standard)
    }

    @discardableResult
    static func migrate(from sourceID: String, to targetID: String,
                        target: UserDefaults) -> Bool {
        guard sourceID != targetID,
              let source = UserDefaults(suiteName: sourceID)?.persistentDomain(forName: sourceID)
        else { return false }
        let destination = target.persistentDomain(forName: targetID) ?? [:]
        guard let merged = mergedDomain(source: source, destination: destination) else { return false }
        target.setPersistentDomain(merged, forName: targetID)
        return true
    }

    /// A completed fork setup is authoritative; fill only keys it has never
    /// saved. Before setup, the official app's explicit choices take priority
    /// over partial preferences a first launch or self-test may have written.
    static func mergedDomain(source: [String: Any],
                             destination: [String: Any]) -> [String: Any]? {
        guard destination[DefaultsKey.importedOfficialSettingsVersion] == nil else { return nil }
        let allowed = SettingsBackupSupport.exportKeys()
        let compatible = source.filter {
            allowed.contains($0.key) && SettingsBackupSupport.valueLooksRight($0.key, $0.value)
        }
        guard !compatible.isEmpty else { return nil }

        let forkWasConfigured = destination[DefaultsKey.hasOnboarded] as? Bool == true
        var merged = destination
        for (key, value) in compatible where !forkWasConfigured || destination[key] == nil {
            merged[key] = value
        }
        merged[DefaultsKey.importedOfficialSettingsVersion] = version
        return merged
    }
}
