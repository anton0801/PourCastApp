import SwiftUI
import UIKit

// MARK: - Pressable: every tappable element scales on press

struct PressableButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(
                configuration.isPressed ? .pcPress : .spring(response: 0.3, dampingFraction: 0.7),
                value: configuration.isPressed
            )
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
}

/// Primary filled action button (teal fill, surface text).
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PCType.body.weight(.semibold))
            .foregroundStyle(Color.surfaceElevated)
            .padding(.vertical, PCSpacing.m)
            .frame(maxWidth: .infinity)
            .background(
                Color.accentTeal.opacity(isEnabled ? 1 : 0.4),
                in: RoundedRectangle(cornerRadius: PCShape.cardRadius, style: .continuous)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(
                configuration.isPressed ? .pcPress : .spring(response: 0.3, dampingFraction: 0.7),
                value: configuration.isPressed
            )
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var pcPrimary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

// MARK: - Haptics map

enum Haptics {
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func medium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}

// MARK: - Stagger: list items enter 40ms apart, capped at 8

private struct StaggerIn: ViewModifier {
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 10)
            .onAppear {
                guard !shown else { return }
                if reduceMotion {
                    shown = true
                } else {
                    withAnimation(.pc.delay(Double(min(index, 8)) * 0.04)) {
                        shown = true
                    }
                }
            }
    }
}

extension View {
    func staggerIn(index: Int) -> some View {
        modifier(StaggerIn(index: index))
    }
}
