import SwiftUI

enum HomeAlert: Equatable {
    case storageFull
    case notificationsOff
    case signInExpired
    case invitation(UUID, String)
}

struct HomeNotice: View {
    let alert: HomeAlert
    let onAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            text
                .font(.app(.golos, 14, weight: 500))
                .foregroundStyle(alertColor)
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

    private var alertColor: Color {
        if case .invitation = alert {
            return Palette.text
        }
        return Palette.urgentText
    }

    private var text: Text {
        switch alert {
        case .storageFull: Text("Could not save on this phone, there is not enough space.")
        case .notificationsOff: Text("Notifications are off, reminders will not come.")
        case .signInExpired: Text("The sign-in has expired. Sign in again.")
        case .invitation(_, let line): Text(verbatim: line)
        }
    }

    private var action: LocalizedStringKey {
        switch alert {
        case .storageFull, .notificationsOff: "Settings"
        case .signInExpired: "Sign in"
        case .invitation: "Open"
        }
    }
}
