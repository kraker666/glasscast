//
// StreamSettings.swift
//
// The user's stream choices (resolution, frame rate, codec), persisted in UserDefaults.
// DAT cannot change a running stream's configuration, so a change is applied by
// stopping the camera and attaching a new one.
//

import Foundation
import MWDATCamera

enum ResolutionOption: String, CaseIterable, Identifiable, Sendable {
  case high
  case medium
  case low

  var id: String { rawValue }

  var label: String {
    switch self {
    case .high: return "High"
    case .medium: return "Medium"
    case .low: return "Low"
    }
  }

  /// Portrait size the SDK delivers at this setting.
  var sizeText: String {
    switch self {
    case .high: return "720×1280"
    case .medium: return "504×896"
    case .low: return "360×640"
    }
  }

  var sdkValue: StreamingResolution {
    switch self {
    case .high: return .high
    case .medium: return .medium
    case .low: return .low
    }
  }
}

enum CodecOption: String, CaseIterable, Identifiable, Sendable {
  /// Frames arrive already decoded; rendered with `VideoFrame.makeUIImage()`.
  case raw
  /// Compressed HEVC frames, decoded on the phone by `VideoFrameDecoder`.
  case hevc

  var id: String { rawValue }

  var label: String {
    switch self {
    case .raw: return "Raw"
    case .hevc: return "HEVC"
    }
  }

  var sdkValue: VideoCodec {
    switch self {
    case .raw: return .raw
    case .hevc: return .hvc1
    }
  }
}

struct StreamSettings: Equatable, Sendable {
  /// Frame rates offered in the picker. DAT accepts 2, 7, 15, 24 and 30.
  static let frameRates: [UInt] = [15, 24, 30]

  var resolution: ResolutionOption = .high
  var frameRate: UInt = 24
  var codec: CodecOption = .raw

  var summary: String {
    "\(resolution.sizeText) · \(frameRate) fps · \(codec.label)"
  }

  private static let resolutionKey = "stream.resolution"
  private static let frameRateKey = "stream.frameRate"
  private static let codecKey = "stream.codec"

  static func load(from defaults: UserDefaults = .standard) -> StreamSettings {
    var settings = StreamSettings()
    if let raw = defaults.string(forKey: resolutionKey), let value = ResolutionOption(rawValue: raw) {
      settings.resolution = value
    }
    let fps = UInt(max(0, defaults.integer(forKey: frameRateKey)))
    if frameRates.contains(fps) {
      settings.frameRate = fps
    }
    if let raw = defaults.string(forKey: codecKey), let value = CodecOption(rawValue: raw) {
      settings.codec = value
    }
    return settings
  }

  func save(to defaults: UserDefaults = .standard) {
    defaults.set(resolution.rawValue, forKey: Self.resolutionKey)
    defaults.set(Int(frameRate), forKey: Self.frameRateKey)
    defaults.set(codec.rawValue, forKey: Self.codecKey)
  }
}
