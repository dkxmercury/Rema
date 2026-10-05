import SwiftUI

struct ReminderPreview: View {
    let when: Date?
    var place: String?
    let summary: String
    let describer: Describer
    let calendar: Calendar

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                SectionLabel(text: "I'll remind")
                if let when {
                    Text(verbatim: describer.shortTime(when))
                        .font(.app(.jost, 44, weight: 500))
                        .frame(height: 48)
                        .contentTransition(.numericText())
                    Text(verbatim: describer.dayTitle(when))
                        .font(.app(.golos, 15, weight: 600))
                } else if let place {
                    Text("By place")
                        .font(.app(.jost, 32, weight: 500))
                        .frame(height: 48, alignment: .leading)
                    Text(verbatim: place)
                        .font(.app(.golos, 15, weight: 600))
                } else {
                    Text("Add a time")
                        .font(.app(.jost, 32, weight: 500))
                        .frame(height: 48, alignment: .leading)
                }
                if !summary.isEmpty {
                    Text(verbatim: summary)
                        .font(.app(.golos, 13))
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                        .contentTransition(.opacity)
                }
            }
            Spacer(minLength: 0)
            if let when {
                let parts = calendar.dateComponents([.hour, .minute], from: when)
                MiniDial(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
                    .animation(Motion.hand, value: when)
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
        .animation(Motion.standard, value: when)
    }
}
