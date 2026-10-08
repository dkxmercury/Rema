import SwiftUI

enum HomeAlert: Equatable {
    case storageFull
    case notificationsOff
    case signInExpired
}

struct HomeNotice: View {
    let alert: HomeAlert
    let onAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(text)
                .font(.app(.golos, 14, weight: 500))
                .foregroundStyle(Palette.urgentText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onAction) {
                Text(action)
            }
            .buttonStyle(SmallButtonStyle(prominent: false))
        }
        .padding(14)
        .panel()
    }

    private var text: LocalizedStringKey {
        switch alert {
        case .storageFull: "Could not save on this phone, there is not enough space."
        case .notificationsOff: "Notifications are off, reminders will not come."
        case .signInExpired: "The sign-in has expired. Sign in again."
        }
    }

    private var action: LocalizedStringKey {
        switch alert {
        case .storageFull, .notificationsOff: "Settings"
        case .signInExpired: "Sign in"
        }
    }
}
