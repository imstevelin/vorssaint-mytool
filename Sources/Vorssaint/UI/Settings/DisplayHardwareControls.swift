// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

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
        }
    }

    private func resetHiDPISelection() {
        let preset = hidpi.defaultProfile(for: display.id)
        width = String(preset.width); height = String(preset.height)
        selectedRate = nil // Never carry another monitor's explicit timing over.
        correctNativePanel = false; panelWidth = ""; panelHeight = ""
        nativeOnly = hidpi.sessions[display.id].map { $0.virtualID == nil } ?? (preset.nativeOnly ?? true)
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

    private var hiDPIControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(DisplayControlText.text("HiDPI 方式", "HiDPI method"), selection: $nativeOnly) {
                Text(DisplayControlText.text("原生縮放", "Native scaling")).tag(true)
                Text(DisplayControlText.text("虛擬鏡像", "Virtual mirror")).tag(false)
            }
            .pickerStyle(.segmented)
            .disabled(hidpi.sessions[display.id] != nil || hidpi.switching != nil || nativeHiDPI.busy)
            HStack {
                Toggle("HiDPI", isOn: Binding(get: { hidpi.sessions[display.id] != nil }, set: { enabled in
                    if enabled { hidpi.enable(display.id, profile: selectedProfile, preservePhysicalRate: selectedRate == nil) }
                    else { hidpi.disable(display.id) }
                }))
                .toggleStyle(.switch)
                .disabled(hidpi.switching != nil || hidpi.confirmationDisplay != nil || nativeHiDPI.busy)
                Spacer()
                if let session = hidpi.sessions[display.id] {
                    Text("\(session.profile.width) × \(session.profile.height) · 2× · \(Int(session.profile.rate)) Hz")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if nativeOnly, hidpi.sessions[display.id] == nil {
                Text(DisplayControlText.text("直接使用實體螢幕；未提供所選模式時不會改用鏡像。", "Uses the physical display directly; unavailable modes do not fall back to mirroring."))
                    .font(.caption).foregroundStyle(.secondary)
                DisclosureGroup(DisplayControlText.text("校正面板尺寸（進階）", "Correct panel dimensions (advanced)")) {
                    Toggle(DisplayControlText.text("本次準備同時校正原生面板尺寸", "Include a native panel size correction"), isOn: $correctNativePanel)
                        .toggleStyle(.checkbox)
                    if correctNativePanel {
                        HStack {
                            TextField(DisplayControlText.text("面板寬度", "Panel width"), text: $panelWidth).frame(width: 90)
                            Text("×")
                            TextField(DisplayControlText.text("面板高度", "Panel height"), text: $panelHeight).frame(width: 90)
                        }.textFieldStyle(.roundedBorder)
                    }
                    Text(DisplayControlText.text("只在系統誤認原生尺寸時填入廠商規格，與介面大小分開；既有校正會保留，還原原生設定可撤銷。", "Use the manufacturer's physical panel specification only when detection is wrong, independently of desktop size. Existing corrections are retained; Restore native configuration removes them."))
                        .font(.caption).foregroundStyle(.secondary)
                }.disabled(nativeHiDPI.busy)
                HStack {
                    Button(DisplayControlText.text("準備原生縮放…", "Prepare native scaling…")) {
                        nativeHiDPI.prepare(display.id, profile: selectedProfile,
                            nativePanelSize: correctNativePanel ? enteredPanelSize : nil)
                    }
                    .disabled(correctNativePanel && !enteredPanelSize.valid)
                    Button(DisplayControlText.text("還原原生設定…", "Restore native configuration…")) {
                        nativeHiDPI.restore(display.id)
                    }
                }.disabled(nativeHiDPI.busy || hidpi.switching != nil || hidpi.confirmationDisplay != nil)
                Text(DisplayControlText.text("準備會備份並加入此型號的縮放模式，相同型號螢幕共用；需管理員授權，並重接螢幕或重新啟動後生效。", "Preparation backs up and adds scaled modes for this display model, shared by matching monitors. Administrator authorization and reconnect or restart are required."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let message = nativeHiDPI.message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            if hidpi.switching == display.id {
                HStack { ProgressView().controlSize(.small); Text(DisplayControlText.preparing) }
            }
            if hidpi.confirmationDisplay == display.id {
                HStack {
                    Button("\(DisplayControlText.keep) (\(hidpi.secondsRemaining))") { hidpi.confirm() }
                        .buttonStyle(.borderedProminent)
                    Button(DisplayControlText.restore) { hidpi.disable(display.id) }
                }
            }
            if hidpi.sessions[display.id] == nil {
                DisclosureGroup(DisplayControlText.custom, isExpanded: $details) {
                    VStack(alignment: .leading, spacing: 8) {
                        Menu("\(width) × \(height)") {
                            ForEach(hidpi.presets(for: display.id), id: \.width) { profile in
                                Button("\(profile.width) × \(profile.height)") {
                                    width = String(profile.width); height = String(profile.height)
                                }
                            }
                        }.fixedSize()
                        HStack {
                            TextField("Width", text: $width).frame(width: 70)
                            Text("×")
                            TextField("Height", text: $height).frame(width: 70)
                            Picker("Hz", selection: Binding(get: { rate }, set: { selectedRate = $0 })) {
                                ForEach(hidpi.refreshRates(for: display.id), id: \.self) { value in
                                    Text("\(value.formatted(.number.precision(.fractionLength(0...2)))) Hz").tag(value)
                                }
                            }.frame(width: 100)
                            Button(DisplayControlText.apply) { hidpi.enable(display.id, profile: selectedProfile, preservePhysicalRate: selectedRate == nil) }
                                .disabled(!VirtualHiDPIService.valid(width: selectedProfile.width, height: selectedProfile.height,
                                                                     rate: selectedProfile.rate)
                                          || hidpi.switching != nil || hidpi.confirmationDisplay != nil)
                        }
                        .textFieldStyle(.roundedBorder)
                    }.padding(.top, 8)
                }
            }
            if let failure = hidpi.failure {
                Text(failure).font(.caption).foregroundStyle(.orange)
                if hidpi.hasPendingRecovery {
                    Button(DisplayControlText.restore) { hidpi.stopAll() }
                }
            }
        }
    }

    private var rate: Double { selectedRate ?? hidpi.defaultProfile(for: display.id).rate }

    private var enteredPanelSize: NativeHiDPIOverride.PanelSize {
        .init(width: Int(panelWidth) ?? 0, height: Int(panelHeight) ?? 0)
    }

    private var selectedProfile: VirtualHiDPIService.Profile {
        .init(width: Int(width) ?? 0, height: Int(height) ?? 0, rate: rate, nativeOnly: nativeOnly)
    }
}
