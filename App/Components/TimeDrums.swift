import SwiftUI

struct TimeDrums: View {
    @Binding var hour: Int
    @Binding var minute: Int

    var body: some View {
        let well = RoundedRectangle(cornerRadius: 14, style: .circular)
        ZStack {
            well
                .fill(Palette.well)
                .insetShadow(well, Palette.wellShadow, blur: 2, y: 1)
                .overlay(well.strokeBorder(Palette.wellBorder, lineWidth: 1))
                .frame(height: 54)
                .padding(.horizontal, 16)
            HStack(spacing: 28) {
                Drum(values: Array(0..<24), selection: $hour)
                    .frame(width: 96)
                Text(verbatim: ":")
                    .font(.app(.jost, 40, weight: 500))
                    .offset(y: -4)
                Drum(values: minuteValues, selection: $minute)
                    .frame(width: 96)
            }
        }
        .frame(height: 212)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .circular))
        .panel()
    }

    private var minuteValues: [Int] {
        var values = Array(stride(from: 0, to: 60, by: 5))
        if !values.contains(minute) {
            values.append(minute)
            values.sort()
        }
        return values
    }
}
