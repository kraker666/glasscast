//
// RootView.swift
//
// Onboarding until the app is registered with Meta AI, then the live view.
//

import MWDATCore
import SwiftUI

struct RootView: View {
  let wearables: any WearablesInterface
  @Bindable var wearablesVM: WearablesViewModel

  var body: some View {
    Group {
      if wearablesVM.registrationState == .registered {
        LiveView(wearables: wearables, wearablesVM: wearablesVM)
      } else {
        OnboardingView(viewModel: wearablesVM)
      }
    }
    .alert("Something went wrong", isPresented: $wearablesVM.showError) {
      Button("OK") { wearablesVM.dismissError() }
    } message: {
      Text(wearablesVM.errorMessage)
    }
  }
}
