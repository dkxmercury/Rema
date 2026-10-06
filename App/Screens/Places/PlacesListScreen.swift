import RemaCore
import SwiftUI

struct PlacesListScreen: View {
    let store: Store
    let onOpen: (Place) -> Void
    let onAdd: () -> Void
    let onBack: () -> Void

    private var places: [Place] {
        store.activePlaces
    }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 0) {
                    PlacesMap(places: places, height: 180)
                        .padding(.top, 14)
                    if !places.isEmpty {
                        list
                            .padding(.top, 12)
                    }
                    Text("Up to 20 places. Any name, only you see it.")
                        .font(.app(.golos, 13))
                        .foregroundStyle(Palette.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 10)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
            .pinnedHeader {
                ScreenHeader(title: "My places", leading: .back, action: onBack)
            }
            PrimaryBar(action: onAdd) {
                Text("Add place")
            }
            .disabled(places.count >= Place.maximumCount)
        }
        .foregroundStyle(Palette.text)
        .animation(Motion.standard, value: places)
    }

    private var list: some View {
        VStack(spacing: 0) {
            ForEach(places) { place in
                Button {
                    onOpen(place)
                } label: {
                    HStack(spacing: 12) {
                        Glyph(paths: PlaceIcon.of(place).paths, size: 20, lineWidth: 1.9, color: Palette.text)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: place.name)
                                .font(.app(.golos, 16, weight: 600))
                            Text(verbatim: details(place))
                                .font(.app(.golos, 12))
                                .foregroundStyle(Palette.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Glyph(paths: Icons.chevron, size: 16, lineWidth: 2, color: Palette.secondary)
                    }
                    .frame(minHeight: place.id == places.last?.id ? 60 : 59)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowPressStyle())
                .transition(.opacity)
                if place.id != places.last?.id {
                    Hairline()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 2)
        .panel()
    }

    private func details(_ place: Place) -> String {
        let count = store.activeReminders.filter { $0.placeIDs.contains(place.id) && !($0.isPlaceOnly && $0.completedThrough != nil) }.count
        let radius = String(localized: "radius \(Int(place.radius)) m", locale: .app)
        let reminders = count == 0 ? String(localized: "no reminders", locale: .app) : String(localized: "\(count) reminders", locale: .app)
        return "\(radius) · \(reminders)"
    }
}
