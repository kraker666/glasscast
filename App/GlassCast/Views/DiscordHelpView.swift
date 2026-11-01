//
// DiscordHelpView.swift
//
// How to put GlassCast on a Discord call with iOS screen share. Kept generic because
// Discord's menus change between versions.
//

import SwiftUI

struct DiscordHelpView: View {
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      List {
        Section("Go live on Discord") {
          StepRow(number: 1, text: "In GlassCast, tap Go live and wait until you see the video.")
          StepRow(number: 2, text: "Open Discord and join a voice channel (or start a call).")
          StepRow(number: 3, text: "Tap Share Screen (sometimes under the call's \"…\" or activity menu), then Start Broadcast.")
          StepRow(number: 4, text: "Switch back to GlassCast. Tap the video once to hide the controls.")
          StepRow(number: 5, text: "To end, stop the broadcast from Discord or the red status-bar pill, then tap Stop here.")
        }
        .listRowBackground(Color.white.opacity(0.06))

        Section("Microphone") {
          Text("Discord uses whichever mic iOS picks. With the glasses connected as a Bluetooth headset, Discord can use the glasses' mics; otherwise it uses the phone's mic.")
          Text("Bluetooth headset audio shares the link with the video. If the picture stutters while you talk, choose the phone's mic in Discord, or lower the stream quality.")
        }

        Section("Tips") {
          Text("Keep the phone close to you and turn off other Bluetooth audio devices.")
          Text("Long streams warm the glasses up. GlassCast shows a warning, and if the glasses stop the camera it waits a minute and tries again on its own.")
          Text("The screen stays awake while you're live. Plug the phone in for long sessions.")
          Text("If GlassCast won't connect after a glasses update, turn Developer Mode back on in the Meta AI app.")
        }
      }
      .navigationTitle("Discord help")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
    }
  }
}
