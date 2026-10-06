import MapKit
import RemaCore
import SwiftUI

enum PlaceIcon: String, CaseIterable {
    case home
    case work
    case sport
    case nature
    case shop
    case star

    var paths: [String] {
        switch self {
        case .home: return Icons.home
        case .work: return Icons.work
        case .sport: return Icons.sport
        case .nature: return Icons.nature
        case .shop: return Icons.shop
        case .star: return Icons.star
        }
    }

    var name: LocalizedStringKey {
        switch self {
        case .home: return "Home"
        case .work: return "Work"
        case .sport: return "Sport"
        case .nature: return "Nature"
        case .shop: return "Shop"
        case .star: return "Favorite"
        }
    }

    static func of(_ place: Place) -> PlaceIcon {
        PlaceIcon(rawValue: place.icon) ?? .star
    }
}

extension Place {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

private struct MapsEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var mapsEnabled: Bool {
        get { self[MapsEnabledKey.self] }
        set { self[MapsEnabledKey.self] = newValue }
    }
}

extension MapStyle {
    static var rema: MapStyle {
        .standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false)
    }
}

struct PlacesMap: View {
    let places: [Place]
    let height: CGFloat
    var radius: CGFloat = 20

    @State private var position: MapCameraPosition = .automatic
    @Environment(\.mapsEnabled) private var mapsEnabled

    var body: some View {
        if mapsEnabled {
            map
        } else {
            Palette.mapBackground
                .frame(height: height)
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .circular))
                .panel(radius: radius)
        }
    }

    private var map: some View {
        Map(position: $position, interactionModes: [.pan, .zoom]) {
            ForEach(places) { place in
                MapCircle(center: place.coordinate, radius: place.radius)
                    .foregroundStyle(Palette.accent.opacity(0.14))
                    .stroke(Palette.accent, style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                Annotation(coordinate: place.coordinate, anchor: .center) {
                    Circle()
                        .fill(Palette.accent)
                        .frame(width: 10, height: 10)
                        .overlay(alignment: .top) {
                            Text(verbatim: place.name)
                                .font(.app(.jost, 12, weight: 600))
                                .foregroundStyle(Palette.text)
                                .fixedSize()
                                .offset(y: 16)
                        }
                } label: {
                    EmptyView()
                }
            }
        }
        .mapStyle(.rema)
        .mapControlVisibility(.hidden)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .circular))
        .panel(radius: radius)
        .onChange(of: places.map(\.id)) { _, _ in
            withAnimation(Motion.standard) { position = .automatic }
        }
        .onAppear {
            if places.isEmpty {
                position = .userLocation(fallback: .automatic)
            }
        }
    }
}

struct PinPickerMap: View {
    @Binding var center: CLLocationCoordinate2D
    @Binding var position: MapCameraPosition
    let radius: Double

    // The search field covers the top of the map, so the pin sits below the center.
    private static let pinShare = 0.6

    static func region(around coordinate: CLLocationCoordinate2D, meters: Double) -> MKCoordinateRegion {
        let shift = meters / 111_000 * (pinShare - 0.5)
        return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: coordinate.latitude + shift, longitude: coordinate.longitude), latitudinalMeters: meters, longitudinalMeters: meters)
    }

    private func pinCoordinate(_ region: MKCoordinateRegion) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: region.center.latitude - region.span.latitudeDelta * (PinPickerMap.pinShare - 0.5), longitude: region.center.longitude)
    }

    @State private var moving = false
    @Environment(\.mapsEnabled) private var mapsEnabled

    var body: some View {
        if mapsEnabled {
            map
        } else {
            Palette.mapBackground
                .overlay { pin(lift: 0) }
        }
    }

    private var map: some View {
        Map(position: $position) {
            MapCircle(center: center, radius: radius)
                .foregroundStyle(Palette.accent.opacity(0.14))
                .stroke(Palette.accent, style: StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
        }
        .mapStyle(.rema)
        .mapControlVisibility(.hidden)
        .onMapCameraChange(frequency: .continuous) { context in
            center = pinCoordinate(context.region)
            if !moving {
                withAnimation(Motion.small) { moving = true }
            }
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            center = pinCoordinate(context.region)
            withAnimation(Motion.small) { moving = false }
            Feedback.play(.select)
        }
        .overlay { pin(lift: moving ? 10 : 0) }
    }

    private func pin(lift: CGFloat) -> some View {
        GeometryReader { proxy in
            Pin()
                .frame(width: 44, height: 57)
                .shadow(color: .black.opacity(lift > 0 ? 0.25 : 0.12), radius: lift > 0 ? 8 : 3, y: lift > 0 ? 10 : 3)
                .position(x: proxy.size.width / 2, y: proxy.size.height * PinPickerMap.pinShare - 28.5 - lift)
        }
        .allowsHitTesting(false)
    }
}

private struct Pin: View {
    var body: some View {
        ZStack(alignment: .top) {
            Path(svg: "M22 57C22 57 0 38 0 22A22 22 0 0 1 44 22C44 38 22 57 22 57Z")
                .fill(Palette.accent)
            Circle()
                .fill(Palette.onAccent)
                .frame(width: 16, height: 16)
                .padding(.top, 14)
        }
    }
}
