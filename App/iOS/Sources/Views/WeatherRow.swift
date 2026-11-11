import Core
import SwiftUI

/// What it was like where and when a line was written, on the line's page under its time
/// and place: "14°C · light rain". One quiet line; tap it for the rest, the day before, the
/// wind, what the numbers are and whose they are. Hold it to take the weather off the line.
struct WeatherRow: View {
    let conditions: Conditions
    let calendar: Calendar
    let onRemove: () -> Void
    @State private var open = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        let words = WeatherWords(conditions: conditions, locale: calendar.locale ?? .current)
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(Motion.settle) { open.toggle() }
            } label: {
                Text(words.brief)
                    .font(Theme.mono)
                    .foregroundStyle(Theme.muted)
                    .frame(minHeight: 22, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("line-weather")
            .accessibilityHint("Shows the day before and the wind")
            .contextMenu {
                Button("Take it off", systemImage: "minus.circle", role: .destructive, action: onRemove)
            }

            if open {
                ForEach(words.more, id: \.self) { row in
                    Text(row)
                        .font(Theme.mono)
                        .foregroundStyle(Theme.muted)
                }
                .accessibilityIdentifier("line-weather-more")
                // What the numbers are, said once, and whose they are, as the licence asks.
                Text("The weather model's value for this square of land, not measured here")
                    .font(Theme.mono)
                    .foregroundStyle(Theme.faint)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
                Button { openURL(Weather.creditLink) } label: {
                    Text(Weather.credit)
                        .font(Theme.mono)
                        .foregroundStyle(Theme.faint)
                        .underline(color: Theme.faint)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("line-weather-credit")
            }
        }
    }
}

/// The weather in the reader's own units and a few words. The notebook keeps it metric; a
/// phone set to miles and Fahrenheit reads it that way.
struct WeatherWords {
    let conditions: Conditions
    let locale: Locale

    /// The hour itself: "14°C · light rain".
    var brief: String {
        let parts = [conditions.temperature.map(temperature), conditions.skyWords].compactMap { $0 }
        return parts.isEmpty ? "weather" : parts.joined(separator: " · ")
    }

    /// The rest, a row each: the day before, the wind, the air.
    var more: [String] {
        var rows: [String] = []
        if let low = conditions.low, let high = conditions.high {
            rows.append("\(temperature(low)) to \(temperature(high)) in the day before")
        }
        if let fallen = conditions.rainBefore {
            rows.append(fallen < 0.05 ? "no rain in the day before" : "\(rain(fallen)) of rain in the day before")
        }
        if let wind = conditions.wind {
            let speed = Measurement(value: wind, unit: UnitSpeed.kilometersPerHour)
                .formatted(.measurement(width: .abbreviated, usage: .wind, numberFormatStyle: .number.precision(.fractionLength(0))).locale(locale))
            rows.append("wind \(speed)" + (conditions.windFromWords.map { " from the \($0)" } ?? ""))
        }
        if let humidity = conditions.humidity {
            rows.append("humidity \((humidity / 100).formatted(.percent.precision(.fractionLength(0)).locale(locale)))")
        }
        return rows
    }

    private func temperature(_ celsius: Double) -> String {
        let words = Measurement(value: celsius, unit: UnitTemperature.celsius)
            .formatted(.measurement(width: .narrow, usage: .weather, numberFormatStyle: .number.precision(.fractionLength(0))).locale(locale))
        // A little under nothing rounds to nothing, not to minus nothing.
        return words.hasPrefix("-0") && !words.dropFirst(2).hasPrefix(where: \.isNumber) ? String(words.dropFirst()) : words
    }

    private func rain(_ millimetres: Double) -> String {
        Measurement(value: millimetres, unit: UnitLength.millimeters)
            .formatted(.measurement(width: .abbreviated, usage: .rainfall, numberFormatStyle: .number.precision(.fractionLength(0...1))).locale(locale))
    }
}

private extension Substring {
    func hasPrefix(where test: (Character) -> Bool) -> Bool { first.map(test) ?? false }
}
