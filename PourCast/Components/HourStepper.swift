import SwiftUI

/// Thumb-friendly hour stepper: tap steps once, holding repeats and
/// accelerates. Mono digits, tile buttons, selection ticks.
struct HourStepper: View {
    let title: String
    @Binding var hour: Int
    var range: ClosedRange<Int> = 0...23

    var body: some View {
        HStack(spacing: PCSpacing.m) {
            Text(title)
                .pcCapsLabel()
            Spacer()
            RepeatStepButton(systemName: "minus", enabled: hour > range.lowerBound) {
                if hour > range.lowerBound { hour -= 1 }
            }
            Text(String(format: "%02d:00", hour))
                .font(PCType.mono)
                .foregroundStyle(Color.textPrimary)
                .frame(minWidth: 58)
            RepeatStepButton(systemName: "plus", enabled: hour < range.upperBound) {
                if hour < range.upperBound { hour += 1 }
            }
        }
    }
}

private struct RepeatStepButton: View {
    let systemName: String
    let enabled: Bool
    let step: () -> Void

    @State private var pressed = false
    @State private var repeatTask: Task<Void, Never>?

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(enabled ? Color.accentTeal : Color.textSecondary.opacity(0.4))
            .frame(width: 34, height: 34)
            .background(Color.accentMuted.opacity(enabled ? 1 : 0.4), in: RoundedRectangle(cornerRadius: PCShape.innerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PCShape.innerRadius, style: .continuous)
                    .strokeBorder(Color.hairline, lineWidth: 1)
            )
            .scaleEffect(pressed ? 0.94 : 1)
            .animation(.pcPress, value: pressed)
            .contentShape(Rectangle())
            .onTapGesture {
                guard enabled else { return }
                Haptics.selection()
                step()
            }
            .onLongPressGesture(minimumDuration: 0.35, maximumDistance: 30) {
                guard enabled else { return }
                startRepeating()
            } onPressingChanged: { pressing in
                pressed = pressing && enabled
                if !pressing { stopRepeating() }
            }
            .onDisappear { stopRepeating() }
            .accessibilityLabel(systemName == "plus" ? "Increase" : "Decrease")
    }

    private func startRepeating() {
        stopRepeating()
        repeatTask = Task { @MainActor in
            var interval: Double = 0.22
            while !Task.isCancelled {
                Haptics.selection()
                step()
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                interval = max(0.07, interval * 0.82)
            }
        }
    }

    private func stopRepeating() {
        repeatTask?.cancel()
        repeatTask = nil
    }
}
