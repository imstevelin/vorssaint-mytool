// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import SwiftUI

/// Tools that share General's destination have their own detail content, so
/// opening General does not also build the audio device and mixer controls.
struct GeneralToolSettings: View {
    let anchor: SettingsSectionAnchor
    @ObservedObject private var l10n = L10n.shared

    private var text: GeneralSettingsStrings { FeatureStrings.generalSettings(l10n.language) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                switch anchor {
                case .panelConfiguration:
                    SettingsCard(title: l10n.s.menuBarSection) {
                        Text(text.panelIntro)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        PanelLayoutEditor()
                        Divider()
                        MenuBarIconSymbolRow()
                        Divider()
                        SettingsRow(symbol: nil, title: text.iconMissingTitle,
                                    caption: text.iconMissingCaption) {
                            Button(l10n.s.showMenuBarIcon) {
                                appDelegate()?.reshowStatusItem()
                            }
                        }
                    }
                    .settingsSectionAnchor(.panelConfiguration, cornerRadius: 16)
                case .mixer:
                    MixerSection(settingsMode: true)
                        .settingsSectionAnchor(.mixer, cornerRadius: 16)
                case .soundOutputSwitcher:
                    SettingsCard(title: l10n.s.soundOutputSwitcherTitle) {
                        SoundOutputSwitcherControls()
                    }
                    .settingsSectionAnchor(.soundOutputSwitcher, cornerRadius: 16)
                    BluetoothAudioRecoverySettings()
                case .audioPriority:
                    SettingsCard(title: l10n.s.audioPrioritySection) {
                        AudioPriorityDisclosure(initiallyExpanded: true, showsHeader: false)
                    }
                    .settingsSectionAnchor(.audioPriority, cornerRadius: 16)
                case .musicBlocking:
                    MusicBlockingSettings()
                        .settingsSectionAnchor(.musicBlocking, cornerRadius: 16)
                default:
                    EmptyView()
                }
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .padding(22)
        }
    }
}

private struct BluetoothAudioRecoverySettings: View {
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.bluetoothAudioRecoveryEnabled) private var enabled = false
    @State private var configured = false
    @State private var busy = false
    @State private var selected: [String: String] = [:]
    @State private var devices: [BluetoothAudioRecoveryService.Device] = []
    @State private var connectedUIDs = Set<String>()
    @State private var recoveryStatus: String?
    private let refresh = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    private var chinese: Bool {
        switch l10n.language {
        case .zhTW, .zhHK, .zhHans: return true
        default: return false
        }
    }

    var body: some View {
        SettingsCard(title: chinese ? "藍牙喇叭連線修復" : "Bluetooth speaker recovery") {
            Toggle(chinese ? "連接指定裝置時自動重啟藍牙服務" : "Restart Bluetooth for selected devices",
                   isOn: $enabled)
                .onChange(of: enabled) { _, _ in
                    BluetoothAudioRecoveryService.shared.syncWithPreferences()
                }
            Text(chinese
                 ? "只有勾選的裝置成為預設音訊輸出時才會執行。重啟會短暫中斷所有藍牙裝置；重新連線不會重複觸發。"
                 : "Runs only when a selected device becomes the default audio output. All Bluetooth devices briefly disconnect; reconnecting does not trigger another restart.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Divider()
            Text(chinese ? "需要自動重啟的裝置" : "Devices that need recovery")
                .font(.headline)
            Text(chinese
                 ? "請先連接藍牙喇叭或耳機，再於下方勾選。可選擇多台，離線後仍會保留選擇；未勾選的裝置不會觸發。"
                 : "Connect a Bluetooth speaker or headphones, then select it below. You can select several devices; selections remain when disconnected. Unselected devices never trigger recovery.")
                .font(.callout)
                .foregroundStyle(.secondary)
            if devices.isEmpty {
                Text(chinese ? "目前沒有可選擇的藍牙音訊裝置。" : "No Bluetooth audio devices are available.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(devices) { device in
                Toggle(isOn: Binding(
                    get: { selected[device.uid] != nil },
                    set: { wanted in
                        if wanted { selected[device.uid] = device.name }
                        else { selected.removeValue(forKey: device.uid) }
                        UserDefaults.standard.set(selected, forKey: DefaultsKey.bluetoothAudioRecoveryDevices)
                        BluetoothAudioRecoveryService.shared.syncWithPreferences()
                        refreshDevices()
                    })) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(device.name)
                            Text(connectedUIDs.contains(device.uid)
                                 ? (chinese ? "已連線" : "Connected")
                                 : (chinese ? "未連線 · 已保留選擇" : "Disconnected · Selection saved"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if devices.filter({ $0.name == device.name }).count > 1 {
                                Text(device.uid).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .toggleStyle(.checkbox)
            }
            if selected.isEmpty {
                Text(chinese ? "尚未指定裝置，自動重啟不會執行。" : "No devices selected. Automatic restart will not run.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Divider()
            Button(chinese ? "立即嘗試修復音量" : "Try volume recovery now") {
                busy = true
                recoveryStatus = nil
                BluetoothAudioRecoveryService.shared.recoverCurrentOutput { result in
                    busy = false
                    switch result {
                    case .restartRequested:
                        recoveryStatus = chinese ? "已送出藍牙重啟要求。請等待喇叭重新連線，再測試音量；若未自動連線，請手動連接。" : "Bluetooth restart requested. Wait for the speaker to reconnect, then test volume; reconnect manually if needed."
                    case .unavailable:
                        recoveryStatus = chinese ? "請先將已勾選的藍牙喇叭設為目前音訊輸出。" : "Select a checked Bluetooth speaker as the current audio output first."
                    case .coolingDown:
                        recoveryStatus = chinese ? "距上次嘗試未滿 30 分鐘，請稍後再試。" : "Recovery was attempted within the last 30 minutes. Try again later."
                    case .authorizationRequired:
                        configured = false
                        recoveryStatus = chinese ? "請先完成下方的重啟授權。" : "Authorize Bluetooth restart below first."
                    case .failed:
                        recoveryStatus = chinese ? "藍牙重啟未成功。請檢查授權或在系統設定重新連接喇叭。" : "Bluetooth restart failed. Check authorization or reconnect the speaker in System Settings."
                    }
                }
            }
            .disabled(busy || !configured || selected.isEmpty)
            Text(chinese
                 ? "適用於連線後音量滑桿有變、實際音量卻不變的情況。會短暫中斷所有藍牙裝置，每 30 分鐘最多一次；無法保證修復所有喇叭。手動修復不需要開啟自動重啟。"
                 : "For a moving volume slider with unchanged speaker loudness. Briefly disconnects all Bluetooth devices, at most once every 30 minutes; recovery is not guaranteed. Automatic restart can remain off.")
                .font(.callout)
                .foregroundStyle(.secondary)
            if let recoveryStatus {
                Text(recoveryStatus).font(.callout).foregroundStyle(.secondary)
            }
            if !configured {
                Button(chinese ? "授權自動重啟" : "Authorize automatic restart") {
                    busy = true
                    BluetoothAudioRecoveryService.install { ok in
                        DispatchQueue.main.async {
                            configured = ok
                            busy = false
                        }
                    }
                }
                .disabled(busy)
                Text(chinese
                     ? "需要管理員密碼進行一次性授權，且只允許執行 /usr/bin/pkill -x bluetoothd。"
                     : "One administrator authorization allows only /usr/bin/pkill -x bluetoothd.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Button(chinese ? "移除重啟授權" : "Remove restart authorization") {
                    busy = true
                    BluetoothAudioRecoveryService.remove { ok in
                        DispatchQueue.main.async {
                            if ok {
                                configured = false
                                enabled = false
                                BluetoothAudioRecoveryService.shared.syncWithPreferences()
                            }
                            busy = false
                        }
                    }
                }
                .disabled(busy)
            }
        }
        .onReceive(refresh) { _ in refreshDevices() }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)) { _ in
            selected = BluetoothAudioRecoveryService.selectedDevices
            refreshDevices()
        }
        .onAppear {
            selected = BluetoothAudioRecoveryService.selectedDevices
            refreshDevices()
            DispatchQueue.global(qos: .utility).async {
                let ready = BluetoothAudioRecoveryService.isConfigured
                DispatchQueue.main.async { configured = ready }
            }
        }
    }
    private func refreshDevices() {
        let connected = BluetoothAudioRecoveryService.availableBluetoothOutputs()
        connectedUIDs = Set(connected.map(\.uid))
        var all = Dictionary(uniqueKeysWithValues: selected.map { ($0.key, $0.value) })
        for device in connected { all[device.uid] = device.name }
        devices = all.map { BluetoothAudioRecoveryService.Device(uid: $0.key, name: $0.value) }
            .sorted { $0.name == $1.name ? $0.uid < $1.uid
                : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

}

/// Draws a system symbol in the menu bar in place of the Vorssaint glyph,
/// picked with one click from a gallery. The last cell takes any other symbol
/// by name, and shows that symbol while it is the one in use.
private struct MenuBarIconSymbolRow: View {
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.menuBarIconSymbol) private var savedName = ""
    @State private var typingName = false

    /// Filtered like the radial menu's icons, so a name a future macOS
    /// drops leaves no empty cell.
    private static let symbols = Defaults.menuBarIconGallery.filter {
        NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil
    }

    private var text: GeneralSettingsStrings { FeatureStrings.generalSettings(l10n.language) }

    var body: some View {
        let name = Defaults.sanitizedMenuBarIconSymbol(savedName)
        let otherName = name.isEmpty || Self.symbols.contains(name) ? "" : name
        VStack(alignment: .leading, spacing: 10) {
            SettingsRow(symbol: nil, title: text.menuBarIconTitle, caption: text.menuBarIconCaption) {
                EmptyView()
            }
            // Eager, so the cell the name popover hangs from is never
            // released while the page scrolls.
            FlowLayoutLite(spacing: 6) {
                cell(selected: name.isEmpty) {
                    savedName = ""
                } label: {
                    vorssaintMark
                }
                .help(text.menuBarIconReset)
                .accessibilityLabel(text.menuBarIconReset)
                ForEach(Self.symbols, id: \.self) { symbol in
                    cell(selected: name == symbol) {
                        savedName = symbol
                    } label: {
                        Image(systemName: symbol)
                    }
                    .help(symbol)
                }
                cell(selected: !otherName.isEmpty) {
                    typingName = true
                } label: {
                    // A name from a newer macOS has nothing to draw here.
                    let drawable = NSImage(systemSymbolName: otherName, accessibilityDescription: nil) != nil
                    Image(systemName: drawable ? otherName : "ellipsis")
                }
                .help(otherName.isEmpty ? text.menuBarIconOther : otherName)
                .accessibilityLabel(text.menuBarIconOther)
                .popover(isPresented: $typingName, arrowEdge: .bottom) {
                    MenuBarIconNameField()
                }
            }
            .padding(.leading, settingsRowTextInset)
        }
    }

    /// The bundled mark even while a symbol replaces it in the menu bar.
    private var vorssaintMark: some View {
        Group {
            if let mark = BlackHoleGlyph.mark(symbolName: "") {
                Image(nsImage: mark)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "circle.fill")
            }
        }
        .frame(maxWidth: 21, maxHeight: 16)
    }

    private func cell<Label: View>(selected: Bool, action: @escaping () -> Void,
                                   @ViewBuilder label: () -> Label) -> some View {
        Button(action: action) {
            label()
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 34, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(selected ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(selected ? Color.accentColor.opacity(0.75) : Color.secondary.opacity(0.13),
                                      lineWidth: selected ? 1.2 : 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Takes any symbol by name. The icon follows the typing: a name this Mac has
/// a symbol for is kept at once, and any other name brings back the icon the
/// field opened with, so a typo never leaves a valid half of the name behind.
private struct MenuBarIconNameField: View {
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.dismiss) private var dismiss
    @AppStorage(DefaultsKey.menuBarIconSymbol) private var savedName = ""
    @State private var draft = ""
    @State private var openingName = ""
    @FocusState private var focused: Bool

    private var text: GeneralSettingsStrings { FeatureStrings.generalSettings(l10n.language) }

    var body: some View {
        let name = Defaults.sanitizedMenuBarIconSymbol(draft)
        VStack(alignment: .leading, spacing: 8) {
            Text(text.menuBarIconOther)
                .font(.headline)
            HStack(spacing: 6) {
                TextField(text.menuBarIconOther, text: $draft, prompt: Text(verbatim: "bolt.fill"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .onSubmit { dismiss() }
                // Kept in place while hidden, so the field does not change
                // width as the name is typed or cleared.
                Button {
                    draft = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(text.menuBarIconReset)
                .accessibilityLabel(text.menuBarIconReset)
                .opacity(draft.isEmpty ? 0 : 1)
                .disabled(draft.isEmpty)
                .accessibilityHidden(draft.isEmpty)
            }
            Text(text.menuBarIconOtherCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !name.isEmpty, BlackHoleGlyph.customMark(named: name) == nil {
                Text(text.menuBarIconUnknown)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(width: 280)
        .onAppear {
            openingName = BlackHoleGlyph.chosenSymbolName
            draft = openingName
            // The popover's window is not key yet while it appears.
            DispatchQueue.main.async { focused = true }
        }
        .onChange(of: draft) { _, newValue in
            let kept = Defaults.menuBarIconSymbolToSave(typed: newValue, opening: openingName) {
                BlackHoleGlyph.customMark(named: $0) != nil
            }
            if kept != savedName { savedName = kept }
        }
    }
}

private struct MusicBlockingSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var musicBlocker = MusicLaunchBlocker.shared
    @State private var replacementRejected = false
    @AppStorage(DefaultsKey.musicBlockEnabled) private var enabled = false
    @AppStorage(DefaultsKey.musicBlockReplacementPath) private var replacementPath = ""
    @AppStorage(DefaultsKey.musicBlockPlayReplacement) private var playReplacement = true

    var body: some View {
        SettingsCard(title: l10n.s.musicBlockSection) {
            SettingsRow(symbol: "playpause.fill", title: l10n.s.musicBlockTitle,
                        caption: l10n.s.musicBlockCaption) {
                Toggle(l10n.s.musicBlockTitle, isOn: $enabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .onChange(of: enabled) { _, _ in
                        musicBlocker.syncWithPreferences()
                    }
            }
            if enabled {
                if !permissions.accessibility {
                    PermissionRow(kind: .accessibility)
                        .padding(.leading, settingsRowTextInset)
                } else if !musicBlocker.isMonitoring {
                    Text(l10n.s.musicBlockUnavailable)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, settingsRowTextInset)
                }
                HStack(spacing: 8) {
                    Text(l10n.s.musicBlockReplacementLabel)
                    Spacer()
                    Text(replacementName)
                        .foregroundStyle(.secondary)
                    Button(l10n.s.musicBlockChooseApp) { chooseReplacement() }
                    if !replacementPath.isEmpty {
                        Button {
                            replacementPath = ""
                            replacementRejected = false
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(.leading, settingsRowTextInset)
                if !replacementPath.isEmpty {
                    Toggle(l10n.s.musicBlockPlayReplacement, isOn: $playReplacement)
                        .padding(.leading, settingsRowTextInset)
                }
                if replacementRejected {
                    Text(l10n.s.musicBlockReplacementBlocked)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, settingsRowTextInset)
                }
            }
        }
    }

    private var replacementName: String {
        guard !replacementPath.isEmpty else { return l10n.s.musicBlockReplacementNone }
        let name = FileManager.default.displayName(atPath: replacementPath)
        return (name as NSString).deletingPathExtension
    }

    private func chooseReplacement() {
        replacementRejected = false
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // Picking the blocked app itself would start a launch-and-kill loop.
        if let bundleID = Bundle(url: url)?.bundleIdentifier,
           MusicLaunchBlocker.blockedBundleIDs.contains(bundleID) {
            replacementRejected = true
            return
        }
        replacementPath = url.path
    }
}
