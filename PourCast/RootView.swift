import SwiftUI

/// Splash overlay lifecycle + the screed-wipe exit, onboarding gate,
/// and the cold-launch/foreground refresh trigger.
struct RootView: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    @State private var showSplash = true
    @State private var mainMounted = false
    @State private var wipeProgress: CGFloat = 0
    @State private var splashOpacity: Double = 1

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.surface.ignoresSafeArea()

                if mainMounted {
                    Group {
                        if settings.onboardingDone {
                            HomeView()
                                .transition(.opacity)
                        } else {
                            OnboardingView {
                                withAnimation(.pcExit) {
                                    settings.onboardingDone = true
                                }
                            }
                            .transition(.opacity)
                        }
                    }
                    .animation(.pcExit, value: settings.onboardingDone)
                }

                if showSplash {
                    SplashView()
                        .opacity(splashOpacity)
                        .mask(alignment: .trailing) {
                            // The screed wipe: splash shrinks from the left,
                            // the destination appears behind the sweep line.
                            Rectangle()
                                .frame(width: max((1 - wipeProgress) * geo.size.width, 0))
                        }
                        .ignoresSafeArea()
                        .zIndex(1)

                    if wipeProgress > 0.001, wipeProgress < 0.999 {
                        Rectangle()
                            .fill(Color.accentTeal)
                            .frame(width: 2, height: geo.size.height * 1.2)
                            .position(x: wipeProgress * geo.size.width, y: geo.size.height / 2)
                            .ignoresSafeArea()
                            .zIndex(2)
                    }
                }
            }
        }
        .preferredColorScheme(settings.theme.colorScheme)
        .task { await runSplash() }
        .onChange(of: scenePhase) { phase in
            if phase == .active, !showSplash {
                Task { await app.refreshIfStale() }
            }
        }
    }

    /// Duration policy: ~2.2s total (min one full 1.8s loop, hard cap 3.0s),
    /// then the 450ms signature exit. Reduce Motion → plain crossfade.
    private func runSplash() async {
        try? await Task.sleep(nanoseconds: 2_200_000_000)
        mainMounted = true
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.35)) { splashOpacity = 0 }
            try? await Task.sleep(nanoseconds: 380_000_000)
        } else {
            withAnimation(.easeInOut(duration: 0.45)) { wipeProgress = 1 }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        showSplash = false
    }
}
