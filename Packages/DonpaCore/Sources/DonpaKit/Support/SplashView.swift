import SwiftUI

/// A brief in-app splash showing the **same** pre-rendered launch image as the
/// iOS `UILaunchScreen` (a single source of truth — no second renderer to drift
/// from it), centered on the matching charcoal ground. Shown for a beat on first
/// launch, then faded out to reveal the title. The image lives in the package's
/// asset catalog (`Bundle.module`); the app catalog has the same file for the OS
/// launch screen, both produced by `Scripts/make-icon.swift --launch`.
struct SplashView: View {
    /// Charcoal ground matching the launch screen's `LaunchBackground`.
    private let ground = Color(red: 0.12, green: 0.12, blue: 0.13)

    var body: some View {
        ZStack {
            ground.ignoresSafeArea()
            Image("LaunchImage", bundle: .module)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 256, height: 256)  // the launch image's natural size
        }
    }
}
