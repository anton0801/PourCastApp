import SwiftUI
import UIKit

// MARK: - Palette "limestone & cure teal"

extension Color {
    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }

    static let surface = dynamic(light: 0xF4F3F0, dark: 0x17191C)
    static let surfaceElevated = dynamic(light: 0xFFFFFF, dark: 0x1F2226)
    static let accentTeal = dynamic(light: 0x0F8A7A, dark: 0x2BB3A0)
    static let accentMuted = dynamic(light: 0xDCEBE8, dark: 0x16332F)
    static let textPrimary = dynamic(light: 0x1C1E21, dark: 0xECEDEE)
    static let textSecondary = dynamic(light: 0x5C6066, dark: 0x9BA1A8)
    static let warningOchre = dynamic(light: 0xC77D00, dark: 0xE09A2B)
    static let dangerClay = dynamic(light: 0xC2402E, dark: 0xE0604C)

    /// 1px borders: black 8% in light, white 8% in dark.
    static let hairline = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 1, alpha: 0.08)
            : UIColor(white: 0, alpha: 0.08)
    })

    /// Soft tint fills behind warning/danger content (token-derived, never system colors).
    static let warningMuted = warningOchre.opacity(0.12)
    static let dangerMuted = dangerClay.opacity(0.12)
}

// MARK: - Type scale (tool-like neutrality; numerals always monospaced)

enum PCType {
    /// 34pt heavy — the verdict word. Scales with Dynamic Type via .largeTitle.
    static let display = Font.system(.largeTitle, design: .default, weight: .heavy)
    /// 22pt semibold section titles.
    static let title = Font.system(.title2, design: .default, weight: .semibold)
    /// 16pt body.
    static let body = Font.system(.callout, design: .default, weight: .regular)
    /// 13pt secondary lines.
    static let footnote = Font.system(.footnote, design: .default, weight: .regular)
    /// 11pt tracked caps labels.
    static let capsLabel = Font.system(.caption2, design: .default, weight: .semibold)
    /// Numeric readouts (temps, hours, scores) — monospaced digits at body size.
    static let mono = Font.system(.callout, design: .default, weight: .medium).monospacedDigit()
    static let monoSmall = Font.system(.caption, design: .default, weight: .medium).monospacedDigit()
    /// Big numeric hero (score).
    static let monoDisplay = Font.system(.title, design: .default, weight: .heavy).monospacedDigit()
    /// Toolbar titles.
    static let navTitle = Font.system(.headline, design: .default, weight: .semibold)
    /// The wordmark in the Home toolbar.
    static let navWordmark = Font.system(.headline, design: .default, weight: .heavy)

    static let displayTracking: CGFloat = -0.5
    static let capsTracking: CGFloat = 1.2
}

extension View {
    /// 11pt semibold, +1.2 tracking, uppercase — the app's label voice.
    func pcCapsLabel(_ color: Color = .textSecondary) -> some View {
        font(PCType.capsLabel)
            .tracking(PCType.capsTracking)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }
}

// MARK: - Shape language: sharp-industrial

enum PCShape {
    static let cardRadius: CGFloat = 10
    static let innerRadius: CGFloat = 6
}

enum PCSpacing {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
}

// MARK: - Motion personality: tight, no bounce theatrics

extension Animation {
    /// The app spring — response 0.38, damping 0.85.
    static let pc = Animation.spring(response: 0.38, dampingFraction: 0.85)
    /// Splash exit / larger transitions.
    static let pcExit = Animation.spring(response: 0.45, dampingFraction: 0.85)
    /// Press feedback: quick in.
    static let pcPress = Animation.easeOut(duration: 0.12)
}

// MARK: - Elevation: hairlines + flat fills, no shadows

private struct PCCard: ViewModifier {
    var padding: CGFloat
    var fill: Color

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(fill, in: RoundedRectangle(cornerRadius: PCShape.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PCShape.cardRadius, style: .continuous)
                    .strokeBorder(Color.hairline, lineWidth: 1)
            )
    }
}

private struct PCTile: ViewModifier {
    var fill: Color

    func body(content: Content) -> some View {
        content
            .background(fill, in: RoundedRectangle(cornerRadius: PCShape.innerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PCShape.innerRadius, style: .continuous)
                    .strokeBorder(Color.hairline, lineWidth: 1)
            )
    }
}

extension View {
    func pcCard(padding: CGFloat = PCSpacing.l, fill: Color = .surfaceElevated) -> some View {
        modifier(PCCard(padding: padding, fill: fill))
    }

    func pcTile(fill: Color = .surfaceElevated) -> some View {
        modifier(PCTile(fill: fill))
    }
}

// MARK: - Icon tiles: SF Symbols .medium inside 28pt squares on accentMuted

struct IconTile: View {
    let systemName: String
    var tint: Color = .accentTeal
    var fill: Color = .accentMuted

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: 28, height: 28)
            .background(fill, in: RoundedRectangle(cornerRadius: PCShape.innerRadius, style: .continuous))
    }
}

// MARK: - Farm-road illustration layer

/// Original, project-local farm-road props. They deliberately sit behind or
/// beside functional content: the product remains a weather utility, while
/// the visuals give it a cheerful road-trip character.
struct FarmPropImage: View {
    let name: String
    var size: CGFloat = 42
    var opacity: Double = 0.82

    var body: some View {
        Image(name)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .opacity(opacity)
            .accessibilityHidden(true)
    }
}

/// Small, non-interactive prop clusters for headers and empty space.
struct FarmPropStrip: View {
    let names: [String]
    var size: CGFloat = 34

    var body: some View {
        HStack(spacing: -6) {
            ForEach(names, id: \.self) { name in
                FarmPropImage(name: name, size: size)
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

/// Four calm scene-specific backdrops for onboarding. The soft white veil
/// keeps every real control and text state legible in either color scheme.
struct FarmOnboardingBackdrop: View {
    let scene: Int

    private var name: String {
        switch scene {
        case 0: "FarmBG-sunrise"
        case 1: "FarmBG-road"
        case 2: "FarmBG-rain"
        default: "FarmBG-dusk"
        }
    }

    var body: some View {
        ZStack {
            Image(name)
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
            Color.surface.opacity(0.78).ignoresSafeArea()
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}
