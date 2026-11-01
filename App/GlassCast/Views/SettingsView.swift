//
// SettingsView.swift
//
// Stream quality picker and glasses info. DAT can't change a running stream, so applying
// new settings re-attaches the camera (a second or two of black).
//

import MWDATCore
import SwiftUI

struct SettingsView: View {
  var viewModel: StreamViewModel
  var wearablesVM: WearablesViewModel

  @Environment(\.dismiss) private var dismiss
  @State private var draft: StreamSettings
  @State private var confirmDisconnect = false

  init(viewModel: StreamViewModel, wearablesVM: WearablesViewModel) {
    self.viewModel = viewModel
    self.wearablesVM = wearablesVM
    self._draft = State(initialValue: viewModel.settings)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Picker("Resolution", selection: $draft.resolution) {
            ForEach(ResolutionOption.allCases) { option in
              Text(option.label).tag(option)
            }
          }
          .pickerStyle(.segmented)
          Text("\(draft.resolution.sizeText) portrait")
            .font(.footnote)
            .foregroundStyle(.secondary)

          Picker("Frame rate", selection: $draft.frameRate) {
            ForEach(StreamSettings.frameRates, id: \.self) { fps in
              Text("\(fps) fps").tag(fps)
            }
          }
          .pickerStyle(.segmented)

          Picker("Codec", selection: $draft.codec) {
            ForEach(CodecOption.allCases) { option in
              Text(option.label).tag(option)
            }
          }
          .pickerStyle(.segmented)
        } header: {
          Text("Stream quality")
        } footer: {
          Text(
            "The glasses send video over Bluetooth, so lower settings often look sharper (less compression). If the picture is blocky or stutters, try Medium or 15 fps. When bandwidth runs short the glasses lower resolution first, then frame rate."
          )
        }

        Section {
          Button(applyTitle) {
            viewModel.apply(draft)
            dismiss()
          }
          .disabled(draft == viewModel.settings && (viewModel.activeSettings == nil || viewModel.activeSettings == draft))
          Button("Reset to defaults (High · 24 fps · Raw)") {
            draft = StreamSettings()
          }
        }

        Section("Glasses") {
          LabeledContent("Name", value: viewModel.deviceName ?? "Not connected")
          LabeledContent("Battery", value: viewModel.batteryLevel.map { "\($0)%" } ?? "—")
          LabeledContent("Temperature", value: thermalText)
          if wearablesVM.requiresFirmwareUpdate {
            Button("Update glasses firmware") {
              Task { await wearablesVM.openFirmwareUpdate() }
            }
          }
          Button("Disconnect GlassCast from Meta AI", role: .destructive) {
            confirmDisconnect = true
          }
        }

        Section("About") {
          LabeledContent("Version", value: appVersion)
          Text("Personal build using Meta's Wearables Device Access Toolkit in Developer Mode. The glasses' capture LED stays on while streaming. Be mindful of people around you.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }
      .navigationTitle("Settings")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
      .confirmationDialog(
        "Disconnect GlassCast?",
        isPresented: $confirmDisconnect,
        titleVisibility: .visible
      ) {
        Button("Disconnect", role: .destructive) {
          viewModel.stop()
          wearablesVM.disconnectGlasses()
          dismiss()
        }
      } message: {
        Text("GlassCast will need to be approved in the Meta AI app again before it can stream.")
      }
    }
  }

  private var applyTitle: String {
    viewModel.activeSettings != nil ? "Apply and restart stream" : "Save"
  }

  private var thermalText: String {
    switch viewModel.thermalLevel {
    case .unknown: return "—"
    case .none, .light: return "Normal"
    case .moderate: return "Warm"
    case .severe: return "Hot"
    case .critical, .emergency, .shutdown: return "Too hot"
    }
  }

  private var appVersion: String {
    let info = Bundle.main.infoDictionary
    let version = info?["CFBundleShortVersionString"] as? String ?? "?"
    let build = info?["CFBundleVersion"] as? String ?? "?"
    return "\(version) (\(build))"
  }
}
