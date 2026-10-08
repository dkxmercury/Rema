import SwiftUI

struct FeaturesScreen: View {
    var onPlaces: () -> Void = {}
    var onFriends: () -> Void = {}
    var onBirthdays: () -> Void = {}
    let onBack: () -> Void

    @Environment(\.openURL) private var openURL

    private struct Feature: Identifiable {
        let id: Int
        let icon: [String]
        let title: LocalizedStringKey
        let text: LocalizedStringKey
        var button: LocalizedStringKey?
        var action: (() -> Void)?
    }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("A quick look at what you can turn on and where to find it.")
                        .font(.app(.golos, 15))
                        .lineSpacing(3)
                        .foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 2)
                        .padding(.top, 14)
                        .padding(.bottom, 4)
                    ForEach(features) { feature in
                        card(feature)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .pinnedHeader {
                ScreenHeader(title: "What Rema can do", leading: .back, action: onBack)
            }
        }
        .foregroundStyle(Palette.text)
    }

    private var features: [Feature] {
        var list: [Feature] = []
        if Remote.shared.isOn(.sync) {
            list.append(Feature(id: 10, icon: Icons.people, title: "With friends", text: "Invite a friend with a link or a QR code, then tap “With friends” when you make a reminder. It comes to everybody at the same moment.", button: "Friends", action: onFriends))
        }
        list.append(Feature(id: 11, icon: Icons.list, title: "Several at once", text: "One phrase can hold several reminders: “tomorrow at 9 call mom, at 12 lunch with Ilya”."))
        list.append(Feature(id: 12, icon: Icons.check, title: "Lists", text: "Write “buy milk, bread and eggs”, and Rema offers a list. Items are ticked one by one."))
        list.append(Feature(id: 13, icon: Icons.calendar, title: "Birthdays and the calendar", text: "Birthdays from contacts become yearly reminders. Meetings from the iPhone calendar show on the home screen next to reminders.", button: "Birthdays", action: onBirthdays))
        if VoiceRecognizer.available {
            list.append(Feature(id: 0, icon: Icons.microphone, title: "By voice", text: "Hold the plus on the home screen and talk. Let go when you are done, and Rema will make sense of the phrase."))
        }
        if #available(iOS 18, *) {
            list.append(Feature(id: 1, icon: Icons.sliders, title: "Control Center and the Action button", text: "Open Control Center, tap + and add the Rema button. If your iPhone has an Action button, assign Rema to it in Settings."))
        }
        list.append(Feature(id: 2, icon: Icons.waveform, title: "Siri and Shortcuts", text: "Say “Remind me in Rema” or “What is next in Rema”. The same actions are in the Shortcuts app.", button: "Open Shortcuts", action: { open("shortcuts://") }))
        list.append(Feature(id: 3, icon: Icons.widgets, title: "Widgets", text: "Touch and hold an empty spot on the Home Screen, tap Edit and then Add Widget. You can tick reminders right on the widget."))
        if Remote.shared.isOn(.liveActivity) {
            list.append(Feature(id: 4, icon: Icons.island, title: "Dynamic Island", text: "When a reminder is less than an hour away, close Rema. The countdown shows up at the top of the screen and on the Lock Screen."))
        }
        list.append(Feature(id: 5, icon: Icons.watch, title: "Apple Watch", text: "The watch app installs together with Rema. If it is not on your watch, install it in the Watch app on your iPhone."))
        if Remote.shared.isOn(.places) {
            list.append(Feature(id: 6, icon: Icons.pin, title: "By place", text: "Write “when I leave work” or “when I get home”. This needs location access and at least one place.", button: "My places", action: onPlaces))
        }
        list.append(Feature(id: 7, icon: Icons.bolt, title: "Urgent", text: "“Urgent” gets through Do Not Disturb and Focus. Add the word “urgent” to the phrase or turn it on in the reminder itself."))
        return list
    }

    private func card(_ feature: Feature) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                let shape = RoundedRectangle(cornerRadius: 12, style: .circular)
                shape
                    .fill(LinearGradient(colors: [Palette.raisedTop, Palette.raisedBottom], startPoint: .top, endPoint: .bottom).shadow(.drop(color: Palette.raisedShadowNear, radius: 1, y: 1)))
                    .insetShadow(shape, Palette.raisedHighlight, y: 1)
                Glyph(paths: feature.icon, size: 20, lineWidth: 2, color: Palette.text)
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(feature.title)
                    .font(.app(.golos, 16, weight: 600))
                Text(feature.text)
                    .font(.app(.golos, 14))
                    .lineSpacing(2)
                    .foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let button = feature.button, let action = feature.action {
                    Button(action: action) {
                        Text(button)
                    }
                    .buttonStyle(SmallButtonStyle(prominent: false))
                    .padding(.top, 8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .panel()
        .accessibilityElement(children: .contain)
    }

    private func open(_ link: String) {
        guard let url = URL(string: link) else { return }
        openURL(url)
    }
}
