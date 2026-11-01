//
// GlassCastApp.swift
//
// Shows the live camera of Ray-Ban Meta glasses full-screen so it can be shared into a
// Discord voice channel with Discord's iOS screen share. Built on Meta's Wearables Device
// Access Toolkit (DAT) in Developer Mode.
//

import MWDATCore
import SwiftUI

@main
struct GlassCastApp: App {
  @State private var wearablesViewModel: WearablesViewModel

  init() {
    do {
      try Wearables.configure()
    } catch {
      NSLog("[GlassCast] Failed to configure Wearables SDK: \(error)")
    }
    self._wearablesViewModel = State(wrappedValue: WearablesViewModel(wearables: Wearables.shared))
  }

  var body: some Scene {
    WindowGroup {
      RootView(wearables: Wearables.shared, wearablesVM: wearablesViewModel)
        .preferredColorScheme(.dark)
        // Meta AI returns here (glasscast://...) after registration and permission prompts.
        .onOpenURL { url in
          wearablesViewModel.handleCallbackURL(url)
        }
    }
  }
}
