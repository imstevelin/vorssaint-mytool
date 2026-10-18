// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

struct InputSourceIndicatorSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @AppStorage(DefaultsKey.inputSourceIndicatorEnabled) private var enabled = false

    var body: some View {
        let text = InputSourceIndicatorStrings.text(l10n.language)
        Form {
            Section(text.title) {
                Toggle(text.enabled, isOn: $enabled)
                    .onChange(of: enabled) { _, value in
                        InputSourceIndicatorService.shared.syncWithPreferences()
                        if value && !permissions.accessibility {
                            permissions.requestAccessibility()
                            permissions.openAccessibilitySettings()
                        }
                    }
                Text(text.caption).font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Text(text.compatibility).font(.caption).foregroundStyle(.secondary)
                if enabled && !permissions.accessibility {
                    PermissionRow(kind: .accessibility)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { InputSourceIndicatorService.shared.syncWithPreferences() }
    }
}
