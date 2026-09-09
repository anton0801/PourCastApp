import SwiftUI

/// S5 — crew defaults. Every control mutates SettingsStore, and Home
/// recomputes immediately through the AppModel pipeline on the way back.
struct PourSetupView: View {
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PCSpacing.l) {
                SegmentTileGroup(
                    title: "Element",
                    options: ElementType.allCases,
                    selection: element
                )
                SegmentTileGroup(
                    title: "Mix",
                    options: MixType.allCases,
                    selection: mix
                )
                SegmentTileGroup(
                    title: "Protection on hand",
                    options: ProtectionType.allCases,
                    selection: protection
                )

                mixNote

                VStack(alignment: .leading, spacing: PCSpacing.s) {
                    Text("Workday")
                        .pcCapsLabel()
                        .padding(.leading, PCSpacing.xs)
                    VStack(spacing: PCSpacing.m) {
                        HourStepper(
                            title: "First pour",
                            hour: workdayStart,
                            range: 0...(settings.defaults.workday.end - 1)
                        )
                        Rectangle().fill(Color.hairline).frame(height: 1)
                        HourStepper(
                            title: "Last pour",
                            hour: workdayEnd,
                            range: (settings.defaults.workday.start + 1)...24
                        )
                    }
                    .padding(PCSpacing.m)
                    .pcTile()
                    Text("Candidate pour hours are scored inside this window only.")
                        .font(PCType.footnote)
                        .foregroundStyle(Color.textSecondary)
                        .padding(.leading, PCSpacing.xs)
                }

                SegmentTileGroup(
                    title: "Units",
                    options: TemperatureUnit.allCases,
                    selection: $settings.unit
                )
            }
            .padding(PCSpacing.l)
        }
        .background(Color.surface.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: PCSpacing.s) {
                    Text("Pour setup")
                        .font(PCType.navTitle)
                        .foregroundStyle(Color.textPrimary)
                    FarmPropStrip(names: ["FarmProp-cone", "FarmProp-wheat"], size: 23)
                }
            }
        }
    }

    /// The one rule that surprises crews — surface it right where mix is picked.
    @ViewBuilder
    private var mixNote: some View {
        if settings.defaults.mix == .winter {
            HStack(spacing: PCSpacing.s) {
                Image(systemName: settings.defaults.protection == .none ? "exclamationmark.triangle" : "snowflake")
                    .font(.system(size: 12, weight: .medium))
                Text(settings.defaults.protection == .none
                     ? "Winter mix needs covering or blankets — unprotected it scores as standard (5°C floor)."
                     : "Winter mix + protection: pours allowed down to −5°C.")
                    .font(PCType.footnote)
            }
            .foregroundStyle(settings.defaults.protection == .none ? Color.warningOchre : Color.accentTeal)
            .padding(PCSpacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                settings.defaults.protection == .none ? Color.warningMuted : Color.accentMuted,
                in: RoundedRectangle(cornerRadius: PCShape.innerRadius, style: .continuous)
            )
        }
    }

    // MARK: - Bindings into the defaults struct

    private var element: Binding<ElementType> {
        Binding(
            get: { settings.defaults.element },
            set: { settings.defaults.element = $0 }
        )
    }

    private var mix: Binding<MixType> {
        Binding(
            get: { settings.defaults.mix },
            set: { settings.defaults.mix = $0 }
        )
    }

    private var protection: Binding<ProtectionType> {
        Binding(
            get: { settings.defaults.protection },
            set: { settings.defaults.protection = $0 }
        )
    }

    private var workdayStart: Binding<Int> {
        Binding(
            get: { settings.defaults.workday.start },
            set: { settings.defaults.workday.start = min($0, settings.defaults.workday.end - 1) }
        )
    }

    private var workdayEnd: Binding<Int> {
        Binding(
            get: { settings.defaults.workday.end },
            set: { settings.defaults.workday.end = max($0, settings.defaults.workday.start + 1) }
        )
    }
}
