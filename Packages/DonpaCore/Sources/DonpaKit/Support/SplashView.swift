import SwiftUI

/// Brief in-app splash showing the same pre-rendered launch image as the iOS
/// `UILaunchScreen` (single source of truth), on the matching charcoal ground,
/// faded out to reveal the title.
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
