/*
 * Derived from WearablesViewModel.swift in Meta's CameraAccess sample
 * (Copyright (c) Meta Platforms, Inc. and affiliates; see LICENSE-META-SAMPLE).
 */

//
// WearablesViewModel.swift
//
// App-wide DAT state: registration with the Meta AI app, the list of linked glasses,
// firmware compatibility, and the Meta AI callback URL.
//

import MWDATCore
import Observation
import SwiftUI

@Observable
@MainActor
final class WearablesViewModel {
  var devices: [DeviceIdentifier]
  var registrationState: RegistrationState
  var showError: Bool = false
  var errorMessage: String = ""
  var requiresFirmwareUpdate: Bool = false

  @ObservationIgnored private var registrationTask: Task<Void, Never>?
  @ObservationIgnored private var deviceStreamTask: Task<Void, Never>?
  private let wearables: any WearablesInterface
  private var deviceCompatibility: [DeviceIdentifier: Compatibility] = [:]
  private var compatibilityListenerTokens: [DeviceIdentifier: any AnyListenerToken] = [:]

  init(wearables: any WearablesInterface) {
    self.wearables = wearables
    self.devices = wearables.devices
    self.registrationState = wearables.registrationState

    deviceStreamTask = Task {
      for await devices in wearables.devicesStream() {
        self.devices = devices
        self.monitorDeviceCompatibility(devices: devices)
      }
    }

    registrationTask = Task {
      for await registrationState in wearables.registrationStateStream() {
        self.registrationState = registrationState
      }
    }
  }

  isolated deinit {
    registrationTask?.cancel()
    deviceStreamTask?.cancel()
  }

  // MARK: - Registration

  func connectGlasses() {
    guard registrationState != .registering else { return }
    Task { @MainActor in
      do {
        try await wearables.startRegistration()
      } catch {
        showError(
          "\(error.localizedDescription)\n\nCheck that Developer Mode is on in the Meta AI app (it turns itself off after glasses firmware updates) and that the phone is online."
        )
      }
    }
  }

  func disconnectGlasses() {
    Task { @MainActor in
      do {
        try await wearables.startUnregistration()
      } catch {
        showError(error.localizedDescription)
      }
    }
  }

  /// Forwards Meta AI callback links (registration and permission results) to the SDK.
  /// Only URLs carrying the `metaWearablesAction` query item are DAT callbacks.
  func handleCallbackURL(_ url: URL) {
    guard
      let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
      components.queryItems?.contains(where: { $0.name == "metaWearablesAction" }) == true
    else {
      return
    }
    Task { @MainActor in
      do {
        _ = try await wearables.handleUrl(url)
      } catch {
        showError(error.localizedDescription)
      }
    }
  }

  // MARK: - Updates

  func openFirmwareUpdate() async {
    do {
      try await wearables.openFirmwareUpdate()
    } catch {
      showError(error.localizedDescription)
    }
  }

  func openDATGlassesAppUpdate() async {
    do {
      try await wearables.openDATGlassesAppUpdate()
    } catch {
      showError(error.localizedDescription)
    }
  }

  // MARK: - Errors

  func showError(_ message: String) {
    errorMessage = message
    showError = true
  }

  func dismissError() {
    showError = false
  }

  // MARK: - Compatibility

  private func monitorDeviceCompatibility(devices: [DeviceIdentifier]) {
    let deviceSet = Set(devices)
    compatibilityListenerTokens = compatibilityListenerTokens.filter { deviceSet.contains($0.key) }
    deviceCompatibility = deviceCompatibility.filter { deviceSet.contains($0.key) }
    updateFirmwareUpdateRequired()

    for deviceId in devices {
      guard compatibilityListenerTokens[deviceId] == nil else { continue }
      guard let device = wearables.deviceForIdentifier(deviceId) else { continue }
      deviceCompatibility[deviceId] = device.compatibility()
      updateFirmwareUpdateRequired()

      let deviceName = device.nameOrId()
      let token = device.addCompatibilityListener { [weak self] compatibility in
        Task { [weak self] in
          await self?.handleCompatibilityChange(compatibility, deviceId: deviceId, deviceName: deviceName)
        }
      }
      compatibilityListenerTokens[deviceId] = token
    }
  }

  private func updateFirmwareUpdateRequired() {
    requiresFirmwareUpdate = deviceCompatibility.values.contains(.deviceUpdateRequired)
  }

  private func handleCompatibilityChange(
    _ compatibility: Compatibility,
    deviceId: DeviceIdentifier,
    deviceName: String
  ) {
    deviceCompatibility[deviceId] = compatibility
    updateFirmwareUpdateRequired()
    if compatibility == .deviceUpdateRequired {
      showError("\(deviceName) needs a firmware update to work with GlassCast.")
    }
  }
}
