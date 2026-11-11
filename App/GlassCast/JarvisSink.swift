//
// JarvisSink.swift
//
// The "Send to Jarvis" capture sink. Takes the current preview frame as JPEG data and
// POSTs it to a user-configured webhook (a Jarvis rig on the LAN) as JSON, signed with
// HMAC-SHA256 over "<unix timestamp>.<raw body bytes>". Foundation + CryptoKit only.
//

import CryptoKit
import Foundation

/// Capture-sink settings, persisted in UserDefaults with the same load/save idiom as
/// `StreamSettings`. Edited in Settings → "Jarvis capture"; not part of `StreamSettings`
/// so changing them never restarts the camera.
struct JarvisSettings: Equatable, Sendable {
  var serverURL: String = "http://192.168.1.10:8644/webhooks/rayban"
  var secret: String = "jogQ4_oT_5JFwpGAzfmG-CoB0dBOSMFbAsaI3VsrYQs"
  /// Attached to every capture; dictate it with the keyboard's microphone button.
  var note: String = ""

  private static let serverURLKey = "jarvis.serverURL"
  private static let secretKey = "jarvis.secret"
  private static let noteKey = "jarvis.note"

  static func load(from defaults: UserDefaults = .standard) -> JarvisSettings {
    var settings = JarvisSettings()
    if let raw = defaults.string(forKey: serverURLKey), !raw.isEmpty {
      settings.serverURL = raw
    }
    if let raw = defaults.string(forKey: secretKey), !raw.isEmpty {
      settings.secret = raw
    }
    if let raw = defaults.string(forKey: noteKey) {
      settings.note = raw
    }
    return settings
  }

  func save(to defaults: UserDefaults = .standard) {
    defaults.set(serverURL, forKey: Self.serverURLKey)
    defaults.set(secret, forKey: Self.secretKey)
    defaults.set(note, forKey: Self.noteKey)
  }
}

enum JarvisSinkError: LocalizedError {
  case badURL(String)
  case encoding
  case badResponse
  case httpStatus(Int)

  var errorDescription: String? {
    switch self {
    case .badURL(let url): return "Invalid Jarvis server URL: \(url)"
    case .encoding: return "Couldn't encode the capture."
    case .badResponse: return "No response from the Jarvis server."
    case .httpStatus(let code): return "Jarvis server error (HTTP \(code))."
    }
  }
}

enum JarvisSink {
  /// The wire protocol allows ~20s before the client gives up.
  private static let timeout: TimeInterval = 20

  /// Signs and POSTs one capture. Returns only on HTTP 202.
  static func send(jpeg: Data, settings: JarvisSettings) async throws {
    guard let url = URL(string: settings.serverURL),
          url.scheme == "http" || url.scheme == "https" else {
      throw JarvisSinkError.badURL(settings.serverURL)
    }

    let capturedAt = ISO8601DateFormatter().string(from: Date())
    let payload: [String: String] = [
      "type": "capture",
      "image_base64": jpeg.base64EncodedString(),
      "captured_at": capturedAt,
      "note": settings.note,
    ]
    let body = try JSONSerialization.data(withJSONObject: payload)

    let timestamp = String(Int(Date().timeIntervalSince1970))
    var message = Data("\(timestamp).".utf8)
    message.append(body)
    let key = SymmetricKey(data: Data(settings.secret.utf8))
    let signature = HMAC<SHA256>.authenticationCode(for: message, using: key)
    let hex = signature.map { String(format: "%02x", $0) }.joined()

    var request = URLRequest(url: url, timeoutInterval: timeout)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(timestamp, forHTTPHeaderField: "X-Webhook-Timestamp")
    request.setValue(hex, forHTTPHeaderField: "X-Webhook-Signature-V2")
    request.httpBody = body

    let (_, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw JarvisSinkError.badResponse
    }
    guard http.statusCode == 202 else {
      throw JarvisSinkError.httpStatus(http.statusCode)
    }
  }
}
