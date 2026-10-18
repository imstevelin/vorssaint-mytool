// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

/// One physical monitor card, shared by Settings and the menu panel.
struct DisplayHardwareControls: View {
    let display: BrightnessDisplay
    var compact = false
    @ObservedObject private var hardware = BrightnessService.shared
    @ObservedObject private var hidpi = VirtualHiDPIService.shared
    @ObservedObject private var audio = AppVolumeMixer.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var width = "1920"
    @State private var height = "1080"
    @State private var selectedRate: Double?
    @State private var details = false

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
            HStack {
                Toggle("HiDPI", isOn: Binding(get: { hidpi.sessions[display.id] != nil }, set: { enabled in
                    if enabled { hidpi.enable(display.id, profile: selectedProfile, preservePhysicalRate: selectedRate == nil) }
                    else { hidpi.disable(display.id) }
                }))
                .toggleStyle(.switch)
                .disabled(hidpi.switching != nil || hidpi.confirmationDisplay != nil)
                Spacer()
                if let session = hidpi.sessions[display.id] {
                    Text("\(session.profile.width) × \(session.profile.height) · 2× · \(Int(session.profile.rate)) Hz")
                        .font(.caption).foregroundStyle(.secondary)
                }
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

    private var selectedProfile: VirtualHiDPIService.Profile {
        .init(width: Int(width) ?? 0, height: Int(height) ?? 0, rate: rate)
    }
}
