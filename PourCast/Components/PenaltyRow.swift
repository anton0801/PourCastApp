import SwiftUI

extension Penalty {
    var title: String {
        switch kind {
        case .tempHardFail: return "Temp outside mix range"
        case .rain: return "Rain after pour"
        case .frost: return "Frost in cure"
        case .hotWindy: return "Hot & windy"
        case .marginalCold: return "Marginal cold"
        case .horizon: return "Past forecast"
        }
    }

    func explanation(unit: TemperatureUnit, calendar: Calendar) -> String {
        switch kind {
        case .tempHardFail:
            let measured = tempC.map { PCFormat.temperature($0, unit: unit) } ?? "Temp"
            let range = rangeC.map {
                " \(PCFormat.temperatureShort($0.lowerBound, unit: unit))…\(PCFormat.temperature($0.upperBound, unit: unit))"
            } ?? ""
            return "\(measured) at pour — outside the mix's\(range) limit. Hard no."
        case .rain:
            return "Wet within 6h of placing — surface washout and scaling risk."
        case .frost:
            let measured = tempC.map { "\(PCFormat.temperature($0, unit: unit)) " } ?? ""
            return "\(measured)during the 48h cure — strength loss risk. Cover or delay."
        case .hotWindy:
            return "Plastic shrinkage risk — morning pour, windbreaks, curing compound."
        case .marginalCold:
            return "Cure hours at 0–5°C — slow strength gain; extend formwork stripping time."
        case .horizon:
            return "Cure extends past the forecast — score capped at 79."
        }
    }
}

/// One scoring penalty: icon tile, hour, minus-points, one-line explanation.
struct PenaltyRow: View {
    let penalty: Penalty
    let unit: TemperatureUnit
    let calendar: Calendar

    var body: some View {
        HStack(alignment: .top, spacing: PCSpacing.m) {
            IconTile(
                systemName: penalty.symbol,
                tint: penalty.points > 0 ? .dangerClay : .textSecondary,
                fill: penalty.points > 0 ? .dangerMuted : .accentMuted
            )

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(penalty.title)
                        .font(PCType.body.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                    if let hour = penalty.hour {
                        Text(PCFormat.weekdayHour(hour, calendar: calendar))
                            .font(PCType.monoSmall)
                            .foregroundStyle(Color.textSecondary)
                    }
                    Spacer(minLength: PCSpacing.s)
                    Text(penalty.points > 0 ? "−\(penalty.points)" : "note")
                        .font(PCType.mono)
                        .foregroundStyle(penalty.points > 0 ? Color.dangerClay : Color.textSecondary)
                }
                Text(penalty.explanation(unit: unit, calendar: calendar))
                    .font(PCType.footnote)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(PCSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pcTile()
    }
}

/// Zero-penalty perfect day.
struct NoPenaltyRow: View {
    var body: some View {
        HStack(spacing: PCSpacing.m) {
            IconTile(systemName: "checkmark.seal")
            Text("Nothing against this window.")
                .font(PCType.body)
                .foregroundStyle(Color.textPrimary)
            Spacer()
        }
        .padding(PCSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pcTile()
    }
}
