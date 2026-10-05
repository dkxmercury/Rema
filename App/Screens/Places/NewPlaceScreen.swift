import MapKit
import RemaCore
import SwiftUI

struct NewPlaceScreen: View {
    let store: Store
    let existing: Place?
    let askToRemember: Bool
    let onSaved: (Place) -> Void
    let onBack: () -> Void

    @State private var remember = false
    @State private var name: String
    @State private var icon: PlaceIcon
    @State private var radius: Double
    @State private var center: CLLocationCoordinate2D
    @State private var position: MapCameraPosition
    @State private var query = ""
    @State private var nameShake = 0
    @State private var confirmingDelete = false
    @FocusState private var nameFocused: Bool
    @FocusState private var searchFocused: Bool

    init(store: Store, existing: Place? = nil, prefill: Place? = nil, askToRemember: Bool = false, onSaved: @escaping (Place) -> Void, onBack: @escaping () -> Void) {
        self.store = store
        self.existing = existing
        self.askToRemember = askToRemember && existing == nil
        self.onSaved = onSaved
        self.onBack = onBack
        let source = existing ?? prefill
        _name = State(initialValue: source?.name ?? "")
        _icon = State(initialValue: source.map(PlaceIcon.of) ?? .home)
        _radius = State(initialValue: source?.radius ?? 150)
        let start = source?.coordinate ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
        _center = State(initialValue: start)
        if let source {
            _position = State(initialValue: .region(PinPickerMap.region(around: source.coordinate, meters: max(source.radius * 5, 600))))
        } else {
            _position = State(initialValue: .userLocation(fallback: .automatic))
        }
    }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    map
                        .padding(.top, 14)
                    if askToRemember {
                        PanelList {
                            ToggleRow(icon: Icons.star, iconColor: Palette.text, title: "Remember place", subtitle: String(localized: "it will appear in My places"), isOn: $remember, minHeight: 60)
                        }
                        .padding(.top, 12)
                    }
                    SectionLabel(text: "Name, anything you like")
                        .padding(.top, 16)
                    nameField
                        .padding(.top, 4)
                    HStack(spacing: 8) {
                        ForEach(suggestions, id: \.key) { suggestion in
                            Chip(title: LocalizedStringKey(suggestion.key), horizontalPadding: 17.5) {
                                name = String(localized: String.LocalizationValue(suggestion.key))
                                icon = suggestion.icon
                                Feedback.play(.select)
                            }
                        }
                    }
                    .padding(.top, 12)
                    HStack(alignment: .firstTextBaseline) {
                        SectionLabel(text: "Radius")
                        Spacer()
                        Text(verbatim: String(localized: "\(Int(radius)) m"))
                            .font(.app(.jost, 18, weight: 600))
                            .contentTransition(.numericText())
                    }
                    .padding(.top, 16)
                    Slider(value: $radius, in: Place.radiusRange, step: 50)
                        .tint(Palette.accent)
                        .frame(height: 28)
                        .padding(.top, 6)
                        .onChange(of: radius) { _, _ in Feedback.play(.select) }
                    iconPicker
                        .padding(.top, 14)
                    if existing != nil {
                        Button(role: .destructive) {
                            confirmingDelete = true
                        } label: {
                            Text("Delete place")
                                .font(.app(.golos, 15, weight: 600))
                                .foregroundStyle(Palette.urgentText)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                        }
                        .buttonStyle(PressableStyle())
                        .padding(.top, 10)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .pinnedHeader {
                ScreenHeader(title: existing == nil ? "New place" : "Place", leading: .back, action: onBack)
            }
            PrimaryBar(action: save) {
                Text(keeps ? LocalizedStringKey("Save place") : LocalizedStringKey("Done"))
            }
        }
        .foregroundStyle(Palette.text)
        .animation(Motion.standard, value: radius)
        .confirmationDialog("Delete place?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                guard let existing else { return }
                Feedback.play(.delete)
                store.deletePlace(existing.id)
                onBack()
            }
        }
        .task {
            guard existing == nil, abs(center.latitude) < 0.0001, abs(center.longitude) < 0.0001 else { return }
            if let location = await LocationService.shared.currentLocation() {
                withAnimation(Motion.standard) {
                    position = .region(PinPickerMap.region(around: location.coordinate, meters: 900))
                }
            }
        }
    }

    private var keeps: Bool {
        !askToRemember || remember
    }

    private var suggestions: [(key: String, icon: PlaceIcon)] {
        [("Home", .home), ("Work", .work), ("Study", .work), ("Country house", .nature)]
    }

    private var map: some View {
        PinPickerMap(center: $center, position: $position, radius: radius)
            .frame(height: 250)
            .overlay(alignment: .top) {
                searchField
                    .padding(12)
            }
            .overlay(alignment: .bottomTrailing) {
                Button(action: locate) {
                    ZStack {
                        RaisedCircle()
                        Glyph(paths: Icons.locate, size: 18, lineWidth: 2, color: Palette.text)
                    }
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel(Text("My location"))
                .padding(12)
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .circular))
            .panel()
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Glyph(paths: Icons.search, size: 18, lineWidth: 2, color: Palette.secondary)
            TextField(text: $query, prompt: Text("Search address").foregroundColor(Palette.secondary)) {
                Text("Search address")
            }
            .font(.app(.golos, 15))
            .tint(Palette.accent)
            .focused($searchFocused)
            .submitLabel(.search)
            .onSubmit { Task { await search() } }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .circular)
                .fill(Palette.well.shadow(.drop(color: .black.opacity(0.12), radius: 1, y: 1)).shadow(.drop(color: .black.opacity(0.08), radius: 6, y: 4)))
        }
    }

    private var nameField: some View {
        TextField(text: $name, prompt: Text("For example, Gym").foregroundColor(Palette.faint)) {
            Text("Place name")
        }
        .font(.app(.golos, 24, weight: 600))
        .tint(Palette.accent)
        .focused($nameFocused)
        .frame(height: 42)
        .padding(.bottom, 6)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.accent).frame(height: 2)
        }
        .modifier(Shake(amount: CGFloat(nameShake)))
        .animation(Motion.small, value: nameShake)
    }

    private var iconPicker: some View {
        HStack {
            ForEach(PlaceIcon.allCases, id: \.self) { option in
                let selected = option == icon
                Button {
                    icon = option
                    Feedback.play(.select)
                } label: {
                    ZStack {
                        if selected {
                            Circle()
                                .fill(Palette.accent.shadow(.drop(color: Palette.accent.opacity(0.3), radius: 5, y: 4)))
                                .insetShadow(Circle(), .black.opacity(0.14), y: -3)
                        } else {
                            RaisedCircle(size: 48)
                        }
                        Glyph(paths: option.paths, size: 20, lineWidth: selected ? 2 : 1.9, color: selected ? Palette.onAccent : Palette.text)
                    }
                    .frame(width: 48, height: 48)
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel(Text(option.name))
                .accessibilityAddTraits(selected ? .isSelected : [])
                if option != PlaceIcon.allCases.last {
                    Spacer(minLength: 0)
                }
            }
        }
        .animation(Motion.small, value: icon)
    }

    private func locate() {
        Task {
            guard let location = await LocationService.shared.currentLocation() else { return }
            withAnimation(Motion.standard) {
                position = .region(PinPickerMap.region(around: location.coordinate, meters: max(radius * 5, 600)))
            }
        }
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        request.region = MKCoordinateRegion(center: center, latitudinalMeters: 50_000, longitudinalMeters: 50_000)
        guard let response = try? await MKLocalSearch(request: request).start(), let item = response.mapItems.first else {
            Feedback.play(.error)
            return
        }
        searchFocused = false
        withAnimation(Motion.standard) {
            position = .region(PinPickerMap.region(around: item.placemark.coordinate, meters: max(radius * 5, 600)))
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard abs(center.latitude) > 0.0001 || abs(center.longitude) > 0.0001 else {
            Feedback.play(.error)
            return
        }
        guard !trimmed.isEmpty || !keeps else {
            nameShake += 1
            nameFocused = true
            Feedback.play(.error)
            return
        }
        var place = existing ?? Place(name: trimmed, icon: icon.rawValue, latitude: center.latitude, longitude: center.longitude, radius: radius, createdAt: Date())
        place.name = trimmed.isEmpty ? String(localized: "Place on the map") : trimmed
        place.icon = icon.rawValue
        place.latitude = center.latitude
        place.longitude = center.longitude
        place.radius = radius
        place.remembered = keeps
        store.save(place)
        Feedback.play(.save)
        Task { _ = await LocationService.shared.requestPermission() }
        if trimmed.isEmpty {
            nameByAddress(place)
        }
        onSaved(place)
    }

    private func nameByAddress(_ place: Place) {
        let store = store
        Task {
            let location = CLLocation(latitude: place.latitude, longitude: place.longitude)
            guard let mark = try? await CLGeocoder().reverseGeocodeLocation(location).first,
                  let address = mark.name ?? mark.thoroughfare,
                  var named = store.places.first(where: { $0.id == place.id }) else { return }
            named.name = address
            store.save(named)
        }
    }
}
