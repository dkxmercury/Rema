import CoreLocation
import SwiftUI

struct CityScreen: View {
    let onBack: () -> Void

    @State private var query = ""
    @State private var results: [CLPlacemark] = []
    @State private var problem: String?
    @State private var locating = false
    @State private var advisor = WeatherAdvisor.shared
    @FocusState private var searchFocused: Bool

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    searchField
                        .padding(.top, 14)
                    PanelList {
                        Button(action: locate) {
                            HStack(spacing: 12) {
                                Glyph(paths: Icons.locate, size: 20, lineWidth: 2, color: Palette.text)
                                Text("My location")
                                    .font(.app(.golos, 16, weight: 600))
                                Spacer(minLength: 8)
                                if locating {
                                    ProgressView()
                                }
                            }
                            .frame(minHeight: 52)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(RowPressStyle())
                        ForEach(Array(results.enumerated()), id: \.offset) { _, mark in
                            Hairline()
                            Button {
                                advisor.choose(mark)
                                Feedback.play(.select)
                                onBack()
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: mark.locality ?? mark.name ?? "")
                                        .font(.app(.golos, 16))
                                    Text(verbatim: [mark.administrativeArea, mark.country].compactMap { $0 }.joined(separator: ", "))
                                        .font(.app(.golos, 13))
                                        .foregroundStyle(Palette.secondary)
                                }
                                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(RowPressStyle())
                        }
                    }
                    .padding(.top, 12)
                    if let problem {
                        Text(verbatim: problem)
                            .font(.app(.golos, 13))
                            .foregroundStyle(Palette.secondary)
                            .padding(.top, 10)
                            .padding(.horizontal, 4)
                    }
                    if let city = advisor.city {
                        Text("Now: \(city)")
                            .font(.app(.golos, 13))
                            .foregroundStyle(Palette.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 10)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .pinnedHeader {
                ScreenHeader(title: "City", leading: .back, action: onBack)
            }
        }
        .foregroundStyle(Palette.text)
        .animation(Motion.standard, value: results.count)
        .task(id: query) {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            do {
                let found = try await advisor.search(query)
                guard !Task.isCancelled else { return }
                results = found
                problem = found.isEmpty && query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 ? String(localized: "Nothing found", bundle: .app, locale: .app) : nil
            } catch {
                guard !Task.isCancelled else { return }
                results = []
                problem = String(localized: "No internet connection. Try again when you are online.", bundle: .app, locale: .app)
            }
        }
    }

    private var searchField: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .circular)
        return HStack(spacing: 8) {
            Glyph(paths: Icons.search, size: 18, lineWidth: 2, color: Palette.secondary)
            TextField(text: $query, prompt: Text("Find a city").foregroundColor(Palette.secondary)) {
                Text("Find a city")
            }
            .font(.app(.golos, 15))
            .tint(Palette.accent)
            .focused($searchFocused)
            .submitLabel(.search)
            .autocorrectionDisabled()
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background {
            shape
                .fill(Palette.well)
                .insetShadow(shape, Palette.wellShadow, blur: 3, y: 1)
        }
        .overlay(shape.strokeBorder(Palette.wellBorder, lineWidth: 1))
    }

    private func locate() {
        locating = true
        Task {
            let found = await advisor.useCurrentLocation()
            locating = false
            if found {
                Feedback.play(.select)
                await advisor.refresh(force: true)
                onBack()
            } else {
                Feedback.play(.error)
            }
        }
    }
}
