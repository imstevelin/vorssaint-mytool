// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
#if canImport(DisplayRecoverySupport)
import DisplayRecoverySupport
#endif

/// One physical monitor card, shared by Settings and the menu panel.
struct DisplayHardwareControls: View {
    let display: BrightnessDisplay
    var compact = false
    @ObservedObject private var hardware = BrightnessService.shared
    @ObservedObject private var hidpi = VirtualHiDPIService.shared
    @ObservedObject private var nativeHiDPI = NativeHiDPIService.shared
    @ObservedObject private var audio = AppVolumeMixer.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var width = "1920"
    @State private var height = "1080"
    @State private var selectedRate: Double?
    @State private var details = false
    @State private var nativeOnly = true
    @State private var selectionEdited = false
    @State private var advancedHiDPI = false
    @State private var correctNativePanel = false
    @State private var panelWidth = ""
    @State private var panelHeight = ""

    private var state: DisplayHardwareState? { hardware.hardwareControls[display.id] }

    var body: some View {
        if !display.isBuiltIn, display.isActive {
            VStack(alignment: .leading, spacing: compact ? 5 : 10) {
                if !compact { hiDPIControls }
                if let volume = state?.values[.volume] {
                    controlSlider(.volume, label: DisplayControlText.volume, value: volume)
                    VolumeFeedbackSoundToggle(compact: compact)
                    HStack {
                        Toggle(DisplayControlText.mute, isOn: Binding(
                            get: { state?.values[.mute].map { $0.current == 1 } ?? (state?.values[.volume]?.current == 0) },
                            set: { _ in toggleMute() }))
                            .toggleStyle(.checkbox)
                            .disabled(state?.pending.contains(.mute) == true)
                        Spacer()
                        if state?.pending.contains(.volume) == true { ProgressView().controlSize(.mini) }
                    }
                } else if state?.values[.mute] != nil {
                    Toggle(DisplayControlText.mute, isOn: Binding(
                        get: { state?.values[.mute]?.current == 1 },
                        set: { _ in toggleMute() }))
                        .toggleStyle(.checkbox)
                }
                if !compact {
                    if let contrast = state?.values[.contrast] {
                        controlSlider(.contrast, label: DisplayControlText.contrast, value: contrast)
                    }
                    if state?.values[.volume] != nil {
                        Picker(DisplayControlText.audio, selection: Binding(
                            get: { hardware.boundAudioUID(for: display.id) ?? "" },
                            set: { hardware.bindAudio($0.isEmpty ? nil : $0, to: display.id) })) {
                            Text(DisplayControlText.none).tag("")
                            ForEach(audio.outputDevices.filter(\.canBeDefaultOutput), id: \.uid) { device in
                                Text(device.name).tag(device.uid)
                            }
                        }
                        if !AXIsProcessTrusted() {
                            Button(DisplayControlText.needsPermission) { Permissions.shared.requestAccessibility() }
                                .buttonStyle(.link)
                        }
                    }
                    if let state, state.values.isEmpty {
                        Text(DisplayControlText.unsupported).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let error = state?.failure { Text(error).font(.caption).foregroundStyle(.orange) }
            }
            .font(compact ? .system(size: 11) : .body)
            .onAppear {
                resetHiDPISelection()
                audio.syncWithPreferences()
            }
            .onChange(of: display.id) { _, _ in resetHiDPISelection() }
            .onChange(of: hidpi.nativeOptions[display.id]) { _, _ in
                guard nativeOnly, !selectionEdited, hidpi.sessions[display.id] == nil,
                      nativeHiDPI.pendingDisplays[display.id] == nil else { return }
                let preset = hidpi.defaultNativeProfile(for: display.id)
                width = String(preset.width); height = String(preset.height)
            }
        }
    }

    private func resetHiDPISelection() {
        let preset = hidpi.defaultNativeProfile(for: display.id)
        width = String(preset.width); height = String(preset.height)
        selectedRate = nil // Never carry another monitor's explicit timing over.
        selectionEdited = false
        correctNativePanel = false; panelWidth = ""; panelHeight = ""
        nativeOnly = hidpi.sessions[display.id].map { $0.virtualID == nil } ?? true
        hidpi.refreshNativeOptions(for: display.id)
    }

    private func toggleMute() {
        hardware.toggleHardwareMute(for: display.id) { applied in
            if applied, hardware.hardwareAudioDisplayID == display.id {
                VolumeFeedbackSound.shared.schedule()
            }
        }
    }

    private func controlSlider(_ control: DisplayHardwareControl, label: String,
                               value: DisplayHardwareValue) -> some View {
        HStack(spacing: 8) {
            Text(label).frame(minWidth: compact ? 45 : 70, alignment: .leading)
            Slider(value: Binding(get: { state?.values[control]?.normalized ?? value.normalized },
                                  set: { target in
                                      hardware.setHardwareControl(control, value: target, for: display.id) { applied in
                                          if applied, control == .volume,
                                             hardware.hardwareAudioDisplayID == display.id {
                                              VolumeFeedbackSound.shared.schedule()
                                          }
                                      }
                                  }), in: 0...1)
                .accessibilityLabel("\(display.name) · \(label)")
            Text("\(Int((value.normalized * 100).rounded()))%")
                .monospacedDigit().foregroundStyle(.secondary).frame(width: 44, alignment: .trailing)
        }
    }

    private func activateSelected() {
        if nativeOnly {
            nativeHiDPI.activate(display.id, profile: selectedProfile,
                preservePhysicalRate: selectedRate == nil,
                panel: correctNativePanel ? enteredPanelSize : nil, useAvailableDefault: !selectionEdited)
        } else {
            hidpi.enable(display.id, profile: selectedProfile, preservePhysicalRate: selectedRate == nil)
        }
    }

    private var selectedValid: Bool {
        nativeOnly
            ? NativeDisplayModes.validRequest(width: selectedProfile.width, height: selectedProfile.height, rate: rate)
                && (!correctNativePanel || enteredPanelSize.valid)
            : VirtualHiDPIService.valid(width: selectedProfile.width, height: selectedProfile.height, rate: rate)
    }

    private var selectionPresets: [VirtualHiDPIService.Profile] {
        guard nativeOnly else { return hidpi.presets(for: display.id) }
        var options = hidpi.nativePresets(for: display.id)
        let current = hidpi.defaultNativeProfile(for: display.id)
        if !options.contains(where: { $0.width == current.width && $0.height == current.height }) {
            options.insert(current, at: 0)
        }
        return options
    }

    private var availableRates: [Double] {
        hidpi.refreshRates(for: display.id, width: selectedProfile.width,
                           height: selectedProfile.height, nativeOnly: nativeOnly)
    }

    private var hiDPIControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle("HiDPI", isOn: Binding(
                    get: { hidpi.sessions[display.id] != nil || nativeHiDPI.pendingDisplays[display.id] != nil },
                    set: { enabled in
                        if enabled { activateSelected() }
                        else {
                            nativeHiDPI.cancel(display.id)
                            if hidpi.sessions[display.id] != nil { hidpi.disable(display.id) }
                        }
                    }))
                    .toggleStyle(.switch)
                    .disabled(hidpi.switching != nil || hidpi.confirmationDisplay != nil || nativeHiDPI.busy
                              || (hidpi.sessions[display.id] == nil && nativeHiDPI.pendingDisplays[display.id] == nil && !selectedValid))
                Spacer()
                if let session = hidpi.sessions[display.id] {
                    Text("\(session.profile.width) × \(session.profile.height) · 2× · \(session.profile.rate.formatted(.number.precision(.fractionLength(0...2)))) Hz")
                        .font(.caption).foregroundStyle(.secondary)
                } else if nativeHiDPI.pendingDisplays[display.id] != nil {
                    Text(DisplayControlText.text("等待啟用", "Waiting to enable"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Text(DisplayControlText.text(nativeOnly ? "原生縮放" : "虛擬鏡像", nativeOnly ? "Native scaling" : "Virtual mirror"))
                .font(.caption).foregroundStyle(.secondary)
            if let message = nativeHiDPI.message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            if hidpi.switching == display.id || (nativeHiDPI.busy && nativeHiDPI.pendingDisplays[display.id] != nil) {
                HStack { ProgressView().controlSize(.small); Text(DisplayControlText.preparing) }
            }
            if hidpi.confirmationDisplay == display.id {
                HStack {
                    Button("\(DisplayControlText.keep) (\(hidpi.secondsRemaining))") { hidpi.confirm() }
                        .buttonStyle(.borderedProminent)
                    Button(DisplayControlText.restore) { hidpi.disable(display.id) }
                }
            }
            if hidpi.sessions[display.id] == nil && nativeHiDPI.pendingDisplays[display.id] == nil {
                DisclosureGroup(DisplayControlText.text("解析度與更新率", "Resolution and refresh rate"), isExpanded: $details) {
                    VStack(alignment: .leading, spacing: 8) {
                        Menu("\(width) × \(height)") {
                            ForEach(selectionPresets, id: \.self) { profile in
                                Button("\(profile.width) × \(profile.height)") {
                                    width = String(profile.width); height = String(profile.height)
                                    selectedRate = profile.rate; selectionEdited = true
                                }
                            }
                        }.fixedSize()
                        HStack {
                            TextField(DisplayControlText.text("寬度", "Width"), text: Binding(
                                get: { width }, set: { width = $0; selectionEdited = true })).frame(width: 70)
                            Text("×")
                            TextField(DisplayControlText.text("高度", "Height"), text: Binding(
                                get: { height }, set: { height = $0; selectionEdited = true })).frame(width: 70)
                            Picker("Hz", selection: Binding(get: { rate }, set: { selectedRate = $0; selectionEdited = true })) {
                                if !availableRates.contains(rate) {
                                    Text("\(rate.formatted(.number.precision(.fractionLength(0...2)))) Hz · \(DisplayControlText.text("目前", "current"))").tag(rate)
                                }
                                ForEach(availableRates, id: \.self) { value in
                                    Text("\(value.formatted(.number.precision(.fractionLength(0...2)))) Hz").tag(value)
                                }
                            }.frame(width: 150)
                            Button(DisplayControlText.apply) { activateSelected() }
                                .disabled(!selectedValid || hidpi.switching != nil || hidpi.confirmationDisplay != nil || nativeHiDPI.busy)
                        }.textFieldStyle(.roundedBorder)
                        Text(DisplayControlText.text("選單依此螢幕提供的模式列出；手動尺寸仍須由 macOS 與硬體接受。", "Menus reflect this display's modes; custom sizes still require macOS and hardware support."))
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(.top, 8)
                }
            }
            DisclosureGroup(DisplayControlText.text("進階顯示選項", "Advanced display options"), isExpanded: $advancedHiDPI) {
                Picker(DisplayControlText.text("HiDPI 方式", "HiDPI method"), selection: $nativeOnly) {
                    Text(DisplayControlText.text("原生縮放（預設）", "Native scaling (default)")).tag(true)
                    Text(DisplayControlText.text("虛擬鏡像（相容性）", "Virtual mirror (compatibility)")).tag(false)
                }
                .disabled(hidpi.sessions[display.id] != nil || nativeHiDPI.pendingDisplays[display.id] != nil
                          || hidpi.switching != nil || nativeHiDPI.busy)
                if nativeOnly, hidpi.sessions[display.id] == nil {
                    Toggle(DisplayControlText.text("校正原生面板尺寸", "Correct native panel dimensions"), isOn: $correctNativePanel)
                        .toggleStyle(.checkbox)
                    if correctNativePanel {
                        HStack {
                            TextField(DisplayControlText.text("面板寬度", "Panel width"), text: $panelWidth).frame(width: 90)
                            Text("×")
                            TextField(DisplayControlText.text("面板高度", "Panel height"), text: $panelHeight).frame(width: 90)
                        }.textFieldStyle(.roundedBorder)
                    }
                    Text(DisplayControlText.text("僅在偵測錯誤時填入廠商的實體面板尺寸；下一次開啟 HiDPI 時一併套用。", "Enter the manufacturer's physical panel dimensions only when detection is wrong; applied the next time HiDPI is enabled."))
                        .font(.caption).foregroundStyle(.secondary)
                    Button(DisplayControlText.text("還原此型號系統設定…", "Restore this model's system configuration…")) {
                        nativeHiDPI.restore(display.id)
                    }.disabled(nativeHiDPI.busy || hidpi.switching != nil || hidpi.confirmationDisplay != nil)
                }
            }.disabled(nativeHiDPI.busy)
            if let failure = hidpi.failure {
                Text(failure).font(.caption).foregroundStyle(.orange)
                if hidpi.hasPendingRecovery { Button(DisplayControlText.restore) { hidpi.stopAll() } }
            }
        }
    }

    private var rate: Double { selectedRate ?? hidpi.defaultNativeProfile(for: display.id).rate }

    private var enteredPanelSize: NativeHiDPIOverride.PanelSize {
        .init(width: Int(panelWidth) ?? 0, height: Int(panelHeight) ?? 0)
    }

    private var selectedProfile: VirtualHiDPIService.Profile {
        .init(width: Int(width) ?? 0, height: Int(height) ?? 0, rate: rate, nativeOnly: nativeOnly)
    }
}
