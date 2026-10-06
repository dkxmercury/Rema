import RemaCore
import SwiftUI

struct PlacesScreen: View {
    let store: Store
    let title: String
    @Binding var placeIDs: [UUID]
    @Binding var trigger: PlaceTrigger
    let onNewPlace: () -> Void
    let onBack: () -> Void

    private var places: [Place] {
        store.activePlaces + store.livePlaces.filter { !$0.remembered && placeIDs.contains($0.id) }
    }

    private var chosen: [Place] {
        places.filter { placeIDs.contains($0.id) }
    }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 0) {
                    if !title.isEmpty {
                        Text(verbatim: title)
                            .font(.app(.golos, 15))
                            .foregroundStyle(Palette.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 6)
                    }
                    Segmented(options: [(PlaceTrigger.arrive, "When I arrive"), (PlaceTrigger.leave, "When I leave")], selection: $trigger)
                        .padding(.top, 12)
                    PlacesMap(places: chosen.isEmpty ? places : chosen, height: 150)
                        .padding(.top, 12)
                    list
                        .padding(.top, 12)
                    Text(trigger == .leave ? LocalizedStringKey("Fires when you leave any of the chosen places") : LocalizedStringKey("Fires when you arrive at any of the chosen places"))
                        .font(.app(.golos, 13))
                        .foregroundStyle(Palette.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 10)
                        .contentTransition(.opacity)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
            .pinnedHeader {
                ScreenHeader(title: "By place", leading: .back, action: onBack)
            }
            PrimaryBar(action: onBack) {
                Text("Done")
            }
        }
        .foregroundStyle(Palette.text)
        .animation(Motion.standard, value: placeIDs)
        .animation(Motion.standard, value: trigger)
        .task {
            _ = await LocationService.shared.requestPermission()
        }
    }

    private var canAdd: Bool {
        store.activePlaces.count < Place.maximumCount
    }

    private var list: some View {
        VStack(spacing: 0) {
            ForEach(places) { place in
                row(place)
                if canAdd || place.id != places.last?.id {
                    Hairline()
                }
            }
            if canAdd {
                Button(action: onNewPlace) {
                    HStack(spacing: 12) {
                        Glyph(paths: Icons.plus, size: 20, lineWidth: 2.2, color: Palette.accentText)
                        Text("New place")
                            .font(.app(.golos, 16, weight: 600))
                            .foregroundStyle(Palette.accentText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 52)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowPressStyle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 2)
        .panel()
    }

    private func row(_ place: Place) -> some View {
        let selected = placeIDs.contains(place.id)
        return Button {
            if selected {
                placeIDs.removeAll { $0 == place.id }
                Feedback.play(.uncheck)
            } else {
                placeIDs.append(place.id)
                Feedback.play(.check)
            }
        } label: {
            HStack(spacing: 12) {
                Glyph(paths: PlaceIcon.of(place).paths, size: 20, lineWidth: 1.9, color: Palette.text)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: place.name)
                        .font(.app(.golos, 16, weight: 600))
                    Text(verbatim: place.remembered ? String(localized: "radius \(Int(place.radius)) m", bundle: .app, locale: .app) : String(localized: "only for this reminder", bundle: .app, locale: .app))
                        .font(.app(.golos, 12))
                        .foregroundStyle(Palette.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                CheckBox(isOn: selected)
            }
            .frame(minHeight: 55)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
