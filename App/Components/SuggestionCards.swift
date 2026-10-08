import RemaCore
import SwiftUI

struct EarlySuggestionCard: View {
    let suggestion: EarlySuggestion
    let onAccept: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .circular)
        HStack(spacing: 10) {
            Glyph(paths: Icons.early, size: 22, lineWidth: 2, color: Palette.accentText)
            VStack(alignment: .leading, spacing: 1) {
                Text(suggestion.minutes == 1_440 ? LocalizedStringKey("Remind a day before too?") : LocalizedStringKey("Remind 2 hours before too?"))
                    .font(.app(.golos, 15, weight: 600))
                Text(reason)
                    .font(.app(.golos, 13))
                    .foregroundStyle(Palette.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onAccept) {
                Text("Yes")
            }
            .buttonStyle(SmallButtonStyle(prominent: false))
            Button(action: onDismiss) {
                Glyph(paths: Icons.close, size: 16, lineWidth: 2.2, color: Palette.secondary)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(RowPressStyle())
            .accessibilityLabel(Text("Dismiss"))
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .padding(.vertical, 10)
        .background(shape.fill(Palette.accent.opacity(0.07)))
        .overlay(shape.strokeBorder(Palette.accent.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
        .accessibilityElement(children: .contain)
    }

    private var reason: LocalizedStringKey {
        switch suggestion.reason {
        case .medical: "Handy before a doctor's visit"
        case .travel: "So you can pack without a rush"
        case .birthday: "So you have time for a gift"
        }
    }
}

struct SnoozeHint: Equatable {
    let reminderID: UUID
    let title: String
}

struct SnoozeHintCard: View {
    let hint: SnoozeHint
    let onAnswer: (Bool) -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Glyph(paths: Icons.clock, size: 20, lineWidth: 2, color: Palette.accentText)
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: 10, style: .circular).fill(Palette.accent.opacity(0.14)))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Move it to another time?")
                        .font(.app(.golos, 16, weight: 600))
                    Text("“\(hint.title)” keeps being put off.")
                        .font(.app(.golos, 14))
                        .lineSpacing(2)
                        .foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 8) {
                Button {
                    onAnswer(false)
                } label: {
                    Text("No thanks")
                        .font(.app(.golos, 14, weight: 600))
                        .foregroundStyle(Palette.secondary)
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(RowPressStyle())
                Button {
                    onAnswer(true)
                } label: {
                    Text("Change time")
                }
                .buttonStyle(SmallButtonStyle(prominent: true))
            }
        }
        .padding(14)
        .panel()
    }
}

struct HabitSuggestionCard: View {
    let suggestion: HabitSuggestion
    let onAnswer: (Bool) -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Glyph(paths: Icons.repeatArrows, size: 20, lineWidth: 2, color: Palette.accentText)
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: 10, style: .circular).fill(Palette.accent.opacity(0.14)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(question)
                        .font(.app(.golos, 16, weight: 600))
                    Text("This is the third week in a row you set “\(suggestion.title)”.")
                        .font(.app(.golos, 14))
                        .lineSpacing(2)
                        .foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 8) {
                Button {
                    onAnswer(false)
                } label: {
                    Text("No thanks")
                        .font(.app(.golos, 14, weight: 600))
                        .foregroundStyle(Palette.secondary)
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(RowPressStyle())
                Button {
                    onAnswer(true)
                } label: {
                    Text("Repeat it")
                }
                .buttonStyle(SmallButtonStyle(prominent: true))
            }
        }
        .padding(.top, 14)
        .padding(.bottom, 12)
        .padding(.leading, 16)
        .padding(.trailing, 14)
        .panel()
        .overlay(RoundedRectangle(cornerRadius: 22, style: .circular).strokeBorder(Palette.accent.opacity(0.45), lineWidth: 1.5))
        .accessibilityElement(children: .contain)
    }

    private var question: LocalizedStringKey {
        switch suggestion.weekday {
        case .monday: "Repeat on Mondays?"
        case .tuesday: "Repeat on Tuesdays?"
        case .wednesday: "Repeat on Wednesdays?"
        case .thursday: "Repeat on Thursdays?"
        case .friday: "Repeat on Fridays?"
        case .saturday: "Repeat on Saturdays?"
        case .sunday: "Repeat on Sundays?"
        }
    }
}
