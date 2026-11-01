//
// LiveView.swift
//
// The main screen: the glasses' camera aspect-fit on black. Tapping anywhere toggles
// "clean mode", which hides every control, the status bar and the home indicator so a
// Discord screen share shows only the video.
//

import MWDATCore
import SwiftUI

struct LiveView: View {
  @State private var viewModel: StreamViewModel
  var wearablesVM: WearablesViewModel

  @State private var cleanMode = false
  @State private var showSettings = false
  @State private var showHelp = false

  init(wearables: any WearablesInterface, wearablesVM: WearablesViewModel) {
    self._viewModel = State(wrappedValue: StreamViewModel(wearables: wearables))
    self.wearablesVM = wearablesVM
  }

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()

      FramePreview(viewModel: viewModel, cleanMode: cleanMode)

      if !cleanMode {
        ControlsOverlay(
          viewModel: viewModel,
          wearablesVM: wearablesVM,
          showSettings: $showSettings,
          showHelp: $showHelp
        )
        .transition(.opacity)
      }
    }
    .contentShape(Rectangle())
    .onTapGesture {
      withAnimation(.easeInOut(duration: 0.2)) { cleanMode.toggle() }
    }
    .statusBarHidden(cleanMode)
    .persistentSystemOverlays(cleanMode ? .hidden : .automatic)
    .sheet(isPresented: $showSettings) {
      SettingsView(viewModel: viewModel, wearablesVM: wearablesVM)
    }
    .sheet(isPresented: $showHelp) {
      DiscordHelpView()
    }
    .alert("GlassCast stopped", isPresented: $viewModel.showError) {
      Button("OK") { viewModel.dismissError() }
    } message: {
      Text(viewModel.errorMessage)
    }
    .alert("Allow camera access", isPresented: $viewModel.showCameraPermissionPrompt) {
      Button("Continue") {
        Task { await viewModel.confirmCameraPermission() }
      }
      Button("Cancel", role: .cancel) {
        viewModel.cancelCameraPermission()
      }
    } message: {
      Text("You'll be taken to the Meta AI app to allow GlassCast to use your glasses' camera, then brought back here.")
    }
  }
}

// MARK: - Video

/// Isolated so per-frame updates only re-render this view.
private struct FramePreview: View {
  var viewModel: StreamViewModel
  let cleanMode: Bool

  var body: some View {
    if let frame = viewModel.currentFrame {
      Image(uiImage: frame)
        .resizable()
        .interpolation(.medium)
        .aspectRatio(contentMode: .fit)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    } else if !cleanMode {
      Placeholder(viewModel: viewModel)
    }
  }
}

private struct Placeholder: View {
  var viewModel: StreamViewModel

  var body: some View {
    VStack(spacing: 14) {
      if viewModel.wantsLive {
        ProgressView()
          .controlSize(.large)
          .tint(.white)
      } else {
        Image(systemName: "eyeglasses")
          .font(.system(size: 54, weight: .semibold))
          .foregroundStyle(.white.opacity(0.8))
      }
      Text(viewModel.statusMessage ?? (viewModel.wantsLive ? "Starting the glasses camera…" : "Tap Go live to start."))
        .font(.callout)
        .foregroundStyle(.white.opacity(0.8))
        .multilineTextAlignment(.center)
        .padding(.horizontal, 40)
      if let retryAt = viewModel.retryAt {
        Text(timerInterval: Date.now...max(retryAt, Date.now), countsDown: true)
          .font(.caption.monospacedDigit())
          .foregroundStyle(.white.opacity(0.6))
      }
    }
  }
}

// MARK: - Controls

private struct ControlsOverlay: View {
  var viewModel: StreamViewModel
  var wearablesVM: WearablesViewModel
  @Binding var showSettings: Bool
  @Binding var showHelp: Bool

  var body: some View {
    VStack(spacing: 0) {
      topBar
      Spacer()
      if viewModel.currentFrame != nil, let message = viewModel.statusMessage {
        Banner(text: message)
          .padding(.bottom, 12)
      }
      updateButtons
      bottomBar
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
  }

  private var topBar: some View {
    HStack(alignment: .top) {
      VStack(alignment: .leading, spacing: 6) {
        StatusPill(label: viewModel.statusLabel, color: statusColor)
        if viewModel.isStreaming || viewModel.activeSettings != nil {
          Text(streamDetails)
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.black.opacity(0.45), in: Capsule())
        }
      }
      Spacer()
      VStack(alignment: .trailing, spacing: 6) {
        if let battery = viewModel.batteryLevel {
          Chip(
            systemImage: batteryIcon(battery),
            text: "\(battery)%",
            tint: battery <= 15 ? .red : .white
          )
        }
        if let warning = viewModel.thermalWarning {
          Chip(
            systemImage: "thermometer.high",
            text: warning,
            tint: viewModel.thermalIsSevere ? .red : .yellow
          )
        }
      }
    }
  }

  @ViewBuilder
  private var updateButtons: some View {
    if viewModel.needsGlassesAppUpdate {
      Button("Update app on glasses") {
        Task { await wearablesVM.openDATGlassesAppUpdate() }
      }
      .buttonStyle(.bordered)
      .padding(.bottom, 10)
    }
    if wearablesVM.requiresFirmwareUpdate {
      Button("Update glasses firmware") {
        Task { await wearablesVM.openFirmwareUpdate() }
      }
      .buttonStyle(.bordered)
      .padding(.bottom, 10)
    }
  }

  private var bottomBar: some View {
    VStack(spacing: 8) {
      HStack(spacing: 16) {
        RoundIconButton(systemImage: "questionmark", label: "How to go live on Discord") {
          showHelp = true
        }
        Button {
          if viewModel.wantsLive { viewModel.stop() } else { viewModel.goLive() }
        } label: {
          Label(viewModel.wantsLive ? "Stop" : "Go live", systemImage: viewModel.wantsLive ? "stop.fill" : "dot.radiowaves.left.and.right")
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .tint(viewModel.wantsLive ? Color.red : Color.accentColor)
        .clipShape(Capsule())
        RoundIconButton(systemImage: "slider.horizontal.3", label: "Stream settings") {
          showSettings = true
        }
      }
      Text("Tap the video to hide all controls.")
        .font(.caption2)
        .foregroundStyle(.white.opacity(0.6))
    }
  }

  private var statusColor: Color {
    if viewModel.isStreaming { return .red }
    if viewModel.isPaused || viewModel.retryAt != nil { return .orange }
    if viewModel.wantsLive { return .yellow }
    return .gray
  }

  private var streamDetails: String {
    var parts: [String] = []
    if viewModel.frameSize != .zero {
      parts.append("\(Int(viewModel.frameSize.width))×\(Int(viewModel.frameSize.height))")
    } else if let active = viewModel.activeSettings {
      parts.append(active.resolution.sizeText)
    }
    if let active = viewModel.activeSettings {
      parts.append(String(format: "%.0f/%d fps", viewModel.measuredFPS, Int(active.frameRate)))
      parts.append(active.codec.label)
    }
    return parts.joined(separator: " · ")
  }

  private func batteryIcon(_ level: Int) -> String {
    if viewModel.chargingState == .charging { return "battery.100.bolt" }
    switch level {
    case ..<13: return "battery.0"
    case ..<38: return "battery.25"
    case ..<63: return "battery.50"
    case ..<88: return "battery.75"
    default: return "battery.100"
    }
  }
}

// MARK: - Small components

private struct StatusPill: View {
  let label: String
  let color: Color

  var body: some View {
    HStack(spacing: 6) {
      Circle().fill(color).frame(width: 8, height: 8)
      Text(label)
        .font(.caption.bold())
        .foregroundStyle(.white)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 5)
    .background(.black.opacity(0.55), in: Capsule())
  }
}

private struct Chip: View {
  let systemImage: String
  let text: String
  let tint: Color

  var body: some View {
    Label(text, systemImage: systemImage)
      .font(.caption.monospacedDigit())
      .foregroundStyle(tint)
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(.black.opacity(0.55), in: Capsule())
  }
}

private struct Banner: View {
  let text: String

  var body: some View {
    Text(text)
      .font(.footnote)
      .foregroundStyle(.white)
      .multilineTextAlignment(.center)
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
  }
}

private struct RoundIconButton: View {
  let systemImage: String
  let label: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .font(.headline)
        .foregroundStyle(.white)
        .frame(width: 48, height: 48)
        .background(.white.opacity(0.15), in: Circle())
    }
    .accessibilityLabel(label)
  }
}
