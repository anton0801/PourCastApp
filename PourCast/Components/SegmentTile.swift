import SwiftUI

protocol SegmentOption: Hashable, Identifiable {
    var tileLabel: String { get }
    var tileSymbol: String? { get }
}

extension ElementType: SegmentOption {
    var tileLabel: String { label }
    var tileSymbol: String? { symbol }
}
extension MixType: SegmentOption {
    var tileLabel: String { label }
    var tileSymbol: String? { nil }
}
extension ProtectionType: SegmentOption {
    var tileLabel: String { shortLabel }
    var tileSymbol: String? { nil }
}
extension TemperatureUnit: SegmentOption {
    var tileLabel: String { label }
    var tileSymbol: String? { nil }
}
extension AppTheme: SegmentOption {
    var tileLabel: String { label }
    var tileSymbol: String? { nil }
}
extension WeatherSource: SegmentOption {
    var tileLabel: String { label }
    var tileSymbol: String? { nil }
}

/// Bespoke segmented control: bordered tiles, pressed scale, selection haptic.
struct SegmentTileGroup<Option: SegmentOption>: View {
    let title: String?
    let options: [Option]
    @Binding var selection: Option
    /// Fires on every tile tap (even re-selection) — onboarding uses it to advance.
    var onSelect: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: PCSpacing.s) {
            if let title {
                Text(title)
                    .pcCapsLabel()
            }
            HStack(spacing: PCSpacing.s) {
                ForEach(options) { option in
                    tile(option)
                }
            }
        }
    }

    private func tile(_ option: Option) -> some View {
        let selected = option == selection
        return Button {
            if !selected {
                Haptics.selection()
                withAnimation(.pc) {
                    selection = option
                }
            }
            onSelect?()
        } label: {
            VStack(spacing: PCSpacing.xs) {
                if let symbol = option.tileSymbol {
                    Image(systemName: symbol)
                        .font(.system(size: 15, weight: .medium))
                }
                Text(option.tileLabel)
                    .font(PCType.footnote.weight(selected ? .semibold : .regular))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(selected ? Color.accentTeal : Color.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, PCSpacing.m)
            .padding(.horizontal, PCSpacing.xs)
            .background(
                selected ? Color.accentMuted : Color.surfaceElevated,
                in: RoundedRectangle(cornerRadius: PCShape.innerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: PCShape.innerRadius, style: .continuous)
                    .strokeBorder(selected ? Color.accentTeal : Color.hairline, lineWidth: selected ? 1.5 : 1)
            )
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
