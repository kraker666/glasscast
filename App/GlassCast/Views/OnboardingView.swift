//
// OnboardingView.swift
//
// First run: explains what GlassCast does and registers it with the Meta AI app.
//

import MWDATCore
import SwiftUI

struct OnboardingView: View {
  var viewModel: WearablesViewModel

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()

      VStack(spacing: 28) {
        Spacer()

        VStack(spacing: 12) {
          Image(systemName: "eyeglasses")
            .font(.system(size: 64, weight: .semibold))
            .foregroundStyle(.white)
          Text("GlassCast")
            .font(.largeTitle.bold())
            .foregroundStyle(.white)
          Text("Your glasses' camera, full screen, ready to share on Discord.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }

        VStack(alignment: .leading, spacing: 16) {
          StepRow(number: 1, text: "In the Meta AI app, turn on Developer Mode for your glasses.")
          StepRow(number: 2, text: "Tap Connect below and approve GlassCast in Meta AI.")
          StepRow(number: 3, text: "Tap Go live, then share your screen in a Discord voice channel.")
        }
        .padding(.horizontal, 8)

        Spacer()

        VStack(spacing: 12) {
          Text("Developer Mode turns itself off after glasses firmware updates. If connecting fails, check it first.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

          Button {
            viewModel.connectGlasses()
          } label: {
            Text(viewModel.registrationState == .registering ? "Connecting…" : "Connect my glasses")
              .font(.headline)
              .frame(maxWidth: .infinity)
              .padding(.vertical, 16)
          }
          .buttonStyle(.borderedProminent)
          .clipShape(Capsule())
          .disabled(viewModel.registrationState == .registering)
        }
      }
      .padding(24)
    }
  }
}

struct StepRow: View {
  let number: Int
  let text: String

  var body: some View {
    HStack(alignment: .top, spacing: 14) {
      Text("\(number)")
        .font(.subheadline.bold())
        .foregroundStyle(.black)
        .frame(width: 26, height: 26)
        .background(Circle().fill(.white))
      Text(text)
        .font(.body)
        .foregroundStyle(.white)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}
