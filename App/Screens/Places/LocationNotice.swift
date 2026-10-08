import CoreLocation
import SwiftUI

struct PlaceNotice: View {
    let text: LocalizedStringKey
    var showsSettings = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 10) {
            Text(text)
                .font(.app(.golos, 14, weight: 500))
                .foregroundStyle(Palette.urgentText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if showsSettings {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                } label: {
                    Text("Settings")
                }
                .buttonStyle(SmallButtonStyle(prominent: false))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(14)
        .panel()
    }
}

extension CLAuthorizationStatus {
    var refused: Bool {
        self == .denied || self == .restricted
    }
}
