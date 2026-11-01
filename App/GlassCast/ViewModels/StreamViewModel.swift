/*
 * Session/stream handling derived from CameraViewModel.swift in Meta's CameraAccess sample
 * (Copyright (c) Meta Platforms, Inc. and affiliates; see LICENSE-META-SAMPLE).
 */

//
// StreamViewModel.swift
//
// Drives GlassCast's single job: keep the glasses' camera on screen. "Go live" starts a
// DeviceSession, checks camera permission, attaches a Camera and starts its Stream. While
// the user wants to be live, any unexpected stop is retried with backoff (longer when the
// glasses are hot). Unlike the sample, backgrounding does not end the session, so the
// stream survives the trip to Discord to start a screen share.
//

import MWDATCamera
import MWDATCore
import Observation
import SwiftUI
import UIKit

@Observable
@MainActor
final class StreamViewModel {
  // MARK: - Settings

  /// Saved settings, used the next time a camera is attached.
  private(set) var settings: StreamSettings
  /// Settings of the camera that is attached right now, if any.
  private(set) var activeSettings: StreamSettings?

  // MARK: - Live state (mirrored from the SDK)

  /// The user pressed Go live and has not pressed Stop. Drives retries and the idle timer.
  private(set) var wantsLive: Bool = false
  private(set) var hasActiveDevice: Bool = false
  private(set) var sessionState: DeviceSessionState = .idle
  private(set) var streamState: StreamState = .stopped

  /// Latest preview frame. Read only by `FramePreview` so ~24 fps updates don't
  /// re-render the controls.
  private(set) var currentFrame: UIImage?
  /// Pixel size of the frames actually arriving (the SDK lowers it when bandwidth is short).
  private(set) var frameSize: CGSize = .zero
  /// Frames per second actually reaching the screen, measured over one-second windows.
  private(set) var measuredFPS: Double = 0

  // MARK: - Glasses state

  private(set) var deviceName: String?
  private(set) var batteryLevel: Int?
  private(set) var chargingState: ChargingState = .unknown
  private(set) var thermalLevel: ThermalLevel = .unknown
  private(set) var hingeState: HingeState = .unknown

  // MARK: - Status and errors

  /// Why we are not live right now (shown on the placeholder and in the overlay).
  private(set) var statusMessage: String?
  /// When the next automatic retry fires, if one is scheduled.
  private(set) var retryAt: Date?
  private(set) var needsGlassesAppUpdate: Bool = false

  var showError: Bool = false
  var errorMessage: String = ""
  /// Confirm prompt before the camera-permission redirect to the Meta AI app.
  var showCameraPermissionPrompt: Bool = false

  // MARK: - Derived

  var isStreaming: Bool { streamState == .streaming }
  var isPaused: Bool { streamState == .paused || sessionState == .paused }
  var isConnecting: Bool {
    wantsLive && !isStreaming && !isPaused && retryAt == nil
  }

  var thermalWarning: String? {
    switch thermalLevel {
    case .moderate: return "Glasses warm"
    case .severe, .critical, .emergency, .shutdown: return "Glasses hot"
    case .unknown, .none, .light: return nil
    }
  }

  var thermalIsSevere: Bool {
    switch thermalLevel {
    case .severe, .critical, .emergency, .shutdown: return true
    default: return false
    }
  }

  var statusLabel: String {
    if isStreaming { return "LIVE" }
    if isPaused { return "PAUSED" }
    if retryAt != nil { return "RETRYING" }
    if wantsLive { return hasActiveDevice ? "CONNECTING" : "WAITING FOR GLASSES" }
    return "OFF"
  }

  // MARK: - Private

  @ObservationIgnored private let wearables: any WearablesInterface
  @ObservationIgnored private let deviceSelector: AutoDeviceSelector
  @ObservationIgnored private var deviceSession: DeviceSession?
  @ObservationIgnored private var camera: MWDATCamera.Camera?
  @ObservationIgnored private let videoFrameDecoder = VideoFrameDecoder()

  @ObservationIgnored private var deviceMonitorTask: Task<Void, Never>?
  @ObservationIgnored private var appLifecycleTask: Task<Void, Never>?
  @ObservationIgnored private var retryTask: Task<Void, Never>?
  @ObservationIgnored private let sessionTokenBag = ListenerTokenBag()
  @ObservationIgnored private let streamTokenBag = ListenerTokenBag()
  @ObservationIgnored private let deviceTokenBag = ListenerTokenBag()

  @ObservationIgnored private var retryAttempt: Int = 0
  /// The next retry should wait for the glasses to cool down.
  @ObservationIgnored private var nextRetryIsCooldown: Bool = false
  /// The camera was stopped on purpose to re-attach it with new settings.
  @ObservationIgnored private var restartingForSettings: Bool = false
  @ObservationIgnored private var isCheckingPermission: Bool = false
  @ObservationIgnored private var fpsWindowStart: Date = .now
  @ObservationIgnored private var fpsWindowFrames: Int = 0

  private static let backoffSeconds: [Int] = [2, 4, 8, 15, 30]
  private static let cooldownSeconds: Int = 60

  // MARK: - Init

  init(wearables: any WearablesInterface) {
    self.wearables = wearables
    self.deviceSelector = AutoDeviceSelector(wearables: wearables)
    self.settings = StreamSettings.load()
    startDeviceMonitoring()
    startAppLifecycleMonitoring()
  }

  isolated deinit {
    deviceMonitorTask?.cancel()
    appLifecycleTask?.cancel()
    retryTask?.cancel()
    deviceSession?.stop()
  }

  // MARK: - User actions

  func goLive() {
    wantsLive = true
    retryAttempt = 0
    nextRetryIsCooldown = false
    needsGlassesAppUpdate = false
    cancelRetry()
    statusMessage = nil
    updateIdleTimer()
    advance()
  }

  func stop() {
    wantsLive = false
    restartingForSettings = false
    cancelRetry()
    statusMessage = nil
    updateIdleTimer()
    endSession()
  }

  /// Saves new settings. If a camera is attached it is stopped and re-attached with them.
  func apply(_ newSettings: StreamSettings) {
    settings = newSettings
    newSettings.save()
    guard let activeCamera = camera, activeSettings != newSettings else { return }
    restartingForSettings = true
    streamState = .stopping
    activeCamera.stop()
  }

  /// Confirmed from the prompt: opens Meta AI to grant camera access, then continues.
  func confirmCameraPermission() async {
    showCameraPermissionPrompt = false
    isCheckingPermission = true
    let granted: Bool
    do {
      granted = try await wearables.requestPermission(.camera) == .granted
    } catch {
      isCheckingPermission = false
      giveUp(error.localizedDescription)
      return
    }
    isCheckingPermission = false
    guard granted else {
      giveUp("Camera access was not allowed in the Meta AI app.")
      return
    }
    advance()
  }

  func cancelCameraPermission() {
    showCameraPermissionPrompt = false
    stop()
  }

  func dismissError() {
    showError = false
  }

  // MARK: - State machine

  /// Moves one step toward a live stream from wherever the SDK currently is.
  private func advance() {
    guard wantsLive else { return }
    switch sessionState {
    case .idle, .stopped:
      guard deviceSession == nil else { return }
      guard hasActiveDevice else {
        statusMessage = "Waiting for your glasses. Put them on, unfold them, and keep them near the phone."
        return
      }
      startSession()
    case .started:
      // Skip while a permission check, prompt or Meta AI redirect is already in flight.
      if camera == nil, !isCheckingPermission, !showCameraPermissionPrompt {
        Task { await startStreamIfPermitted() }
      }
    case .starting, .paused, .stopping:
      // Wait for the SDK to settle; the state observer calls advance() again.
      return
    }
  }

  private func startSession() {
    do throws(DeviceSessionError) {
      let session = try wearables.createSession(deviceSelector: deviceSelector)
      deviceSession = session
      // Subscribe before start() so no initial state transitions are missed.
      observeSession(session)
      sessionState = .starting
      try session.start()
    } catch {
      handleSessionError(error)
      sessionState = .idle
      cleanupSession()
      scheduleRetry()
    }
  }

  private func endSession() {
    guard let session = deviceSession else { return }
    sessionState = .stopping
    session.stop()
  }

  /// Checks camera permission silently; asks before redirecting to Meta AI if it is missing.
  private func startStreamIfPermitted() async {
    guard !isCheckingPermission else { return }
    isCheckingPermission = true
    defer { isCheckingPermission = false }
    do {
      if try await wearables.checkPermissionStatus(.camera) == .granted {
        beginStream()
      } else {
        showCameraPermissionPrompt = true
      }
    } catch {
      statusMessage = error.localizedDescription
      scheduleRetry()
    }
  }

  private func beginStream() {
    guard wantsLive, camera == nil, let session = deviceSession, session.state == .started else { return }
    let streamSettings = settings
    let config = StreamConfiguration(
      videoCodec: streamSettings.codec.sdkValue,
      resolution: streamSettings.resolution.sdkValue,
      frameRate: streamSettings.frameRate
    )
    do throws(DeviceSessionError) {
      guard let newCamera = try session.addCamera(config: config) else {
        statusMessage = "Couldn't attach the glasses camera."
        scheduleRetry()
        return
      }
      camera = newCamera
      activeSettings = streamSettings
      setupStreamListeners(for: newCamera.stream, codec: streamSettings.codec)
      streamState = .starting
      newCamera.stream.start()
    } catch {
      camera = nil
      activeSettings = nil
      handleSessionError(error)
      scheduleRetry()
    }
  }

  /// Ends the attempt for good: no more retries, the session is closed, the user is told why.
  private func giveUp(_ message: String) {
    wantsLive = false
    cancelRetry()
    updateIdleTimer()
    endSession()
    statusMessage = message
    errorMessage = message
    showError = true
  }

  // MARK: - Retry

  private func scheduleRetry() {
    guard wantsLive, retryTask == nil else { return }
    let seconds: Int
    if nextRetryIsCooldown {
      seconds = Self.cooldownSeconds
      nextRetryIsCooldown = false
    } else {
      seconds = Self.backoffSeconds[min(retryAttempt, Self.backoffSeconds.count - 1)]
    }
    retryAttempt += 1
    retryAt = Date.now.addingTimeInterval(TimeInterval(seconds))
    retryTask = Task { @MainActor [weak self] in
      try? await Task.sleep(for: .seconds(seconds))
      guard let self, !Task.isCancelled else { return }
      self.retryTask = nil
      self.retryAt = nil
      self.advance()
    }
  }

  private func cancelRetry() {
    retryTask?.cancel()
    retryTask = nil
    retryAt = nil
  }

  /// Skips the wait when something suggests a retry would work now (glasses came back,
  /// app returned to the foreground). Cooldown waits are kept.
  private func retryNowIfWaiting() {
    guard wantsLive, !isStreaming else { return }
    if retryTask != nil {
      guard !thermalIsSevere else { return }
      cancelRetry()
    }
    advance()
  }

  private func updateIdleTimer() {
    UIApplication.shared.isIdleTimerDisabled = wantsLive
  }

  // MARK: - Device monitoring

  private func startDeviceMonitoring() {
    deviceMonitorTask = Task { [weak self] in
      guard let self else { return }
      for await deviceId in deviceSelector.activeDeviceStream() {
        self.handleActiveDeviceChange(deviceId)
      }
    }
  }

  private func handleActiveDeviceChange(_ deviceId: DeviceIdentifier?) {
    hasActiveDevice = deviceId != nil
    deviceTokenBag.clear()
    guard let deviceId, let device = wearables.deviceForIdentifier(deviceId) else {
      deviceName = nil
      batteryLevel = nil
      chargingState = .unknown
      thermalLevel = .unknown
      hingeState = .unknown
      return
    }
    deviceName = device.nameOrId()
    batteryLevel = device.batteryLevel
    chargingState = device.chargingState
    thermalLevel = device.thermalLevel
    hingeState = device.hingeState
    device.addDeviceStateListener { [weak self] state in
      Task { @MainActor in self?.applyDeviceState(state) }
    }.store(in: deviceTokenBag)
    retryNowIfWaiting()
  }

  private func applyDeviceState(_ state: DeviceState) {
    batteryLevel = state.batteryLevel
    chargingState = state.chargingState
    thermalLevel = state.thermalLevel
    hingeState = state.hingeState
  }

  private func startAppLifecycleMonitoring() {
    appLifecycleTask = Task { [weak self] in
      guard let self else { return }
      for await _ in NotificationCenter.default.notifications(named: UIApplication.didBecomeActiveNotification) {
        self.retryNowIfWaiting()
      }
    }
  }

  // MARK: - Session observation

  private func observeSession(_ session: DeviceSession) {
    session.statePublisher.listen { [weak self] state in
      Task { @MainActor in self?.handleSessionStateChange(state) }
    }.store(in: sessionTokenBag)
    session.errorPublisher.listen { [weak self] error in
      Task { @MainActor in self?.handleSessionError(error) }
    }.store(in: sessionTokenBag)
  }

  private func handleSessionStateChange(_ state: DeviceSessionState) {
    sessionState = state
    switch state {
    case .started:
      advance()
    case .paused:
      statusMessage = "The glasses paused the session. It resumes on its own."
    case .stopped:
      clearStreamResources()
      cleanupSession()
      scheduleRetry()
    case .idle, .starting, .stopping:
      break
    }
  }

  private func handleSessionError(_ error: DeviceSessionError) {
    switch error {
    case .datAppOnTheGlassesUpdateRequired:
      needsGlassesAppUpdate = true
      giveUp("The DAT app on your glasses needs an update. Tap \"Update app on glasses\".")
    case .insufficientSDKVersion:
      giveUp("This GlassCast build is too old for your glasses. Rebuild it with a newer DAT SDK.")
    case .batteryCritical:
      giveUp("Glasses battery is too low to stream. Charge them and try again.")
    case .thermalCritical, .thermalEmergency, .peakPowerShutdown:
      nextRetryIsCooldown = true
      statusMessage = "The glasses got too hot and stopped. Waiting for them to cool down."
    case .noEligibleDevice:
      statusMessage = "No glasses available. Check they are on, unfolded, and connected in the Meta AI app."
    case .dwaOutOfStuRange:
      // Non-blocking compatibility warning; streaming continues.
      break
    default:
      statusMessage = error.localizedDescription
    }
  }

  /// Terminal session cleanup so the next start creates a fresh session.
  private func cleanupSession() {
    sessionTokenBag.clear()
    deviceSession = nil
  }

  // MARK: - Stream observation

  private func setupStreamListeners(for stream: MWDATCamera.Stream, codec: CodecOption) {
    stream.statePublisher.listen { [weak self] state in
      Task { @MainActor in self?.handleStreamStateChange(state) }
    }.store(in: streamTokenBag)

    stream.videoFramePublisher.listen { [weak self] frame in
      guard let self else { return }
      // Decode off the main actor; only the finished image hops over.
      let image = self.makeImage(from: frame, codec: codec)
      Task { @MainActor [weak self] in
        self?.present(image)
      }
    }.store(in: streamTokenBag)

    stream.errorPublisher.listen { [weak self] error in
      Task { @MainActor in self?.handleStreamError(error) }
    }.store(in: streamTokenBag)
  }

  nonisolated private func makeImage(from frame: VideoFrame, codec: CodecOption) -> UIImage? {
    switch codec {
    case .raw: return frame.makeUIImage()
    case .hevc: return videoFrameDecoder.decode(frame.sampleBuffer)
    }
  }

  private func present(_ image: UIImage?) {
    guard let image, camera != nil else { return }
    // Nothing on screen to update while backgrounded (e.g. while starting the Discord share).
    guard UIApplication.shared.applicationState != .background else { return }
    currentFrame = image
    let size = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
    if size != frameSize {
      frameSize = size
    }
    fpsWindowFrames += 1
    let elapsed = Date.now.timeIntervalSince(fpsWindowStart)
    if elapsed >= 1 {
      measuredFPS = Double(fpsWindowFrames) / elapsed
      fpsWindowFrames = 0
      fpsWindowStart = .now
    }
  }

  private func handleStreamStateChange(_ state: StreamState) {
    streamState = state
    switch state {
    case .streaming:
      retryAttempt = 0
      nextRetryIsCooldown = false
      statusMessage = nil
    case .paused:
      statusMessage = "Paused from the glasses. Tap the glasses' touchpad to resume."
    case .waitingForDevice:
      statusMessage = "Waiting for the glasses to start the camera…"
    case .stopped:
      clearStreamResources()
      if restartingForSettings {
        restartingForSettings = false
        advance()
      } else if sessionState == .started {
        scheduleRetry()
      }
    case .starting, .stopping:
      break
    }
  }

  private func handleStreamError(_ error: StreamError) {
    switch error {
    case .permissionDenied:
      giveUp("Camera access for GlassCast is off. Allow it in the Meta AI app, then tap Go live.")
    case .batteryLow:
      giveUp("Glasses battery is too low to stream. Charge them and try again.")
    case .thermalHot, .peakPowerLimit:
      nextRetryIsCooldown = true
      statusMessage = "The glasses got too hot and stopped the camera. Waiting for them to cool down."
    case .hingesClosed:
      statusMessage = "The glasses are folded. Unfold them to resume."
    case .photoCaptureFailed:
      break
    default:
      statusMessage = error.localizedDescription
    }
  }

  /// Single stream-teardown point. `camera.stop()` is idempotent and needed when the
  /// stream ends on its own while the session stays up (teardown cascades parent to
  /// child only).
  private func clearStreamResources() {
    streamTokenBag.clear()
    camera?.stop()
    camera = nil
    activeSettings = nil
    streamState = .stopped
    currentFrame = nil
    frameSize = .zero
    measuredFPS = 0
    fpsWindowFrames = 0
  }
}
