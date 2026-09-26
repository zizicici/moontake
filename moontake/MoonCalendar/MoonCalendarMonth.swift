import Foundation

/// A civil month in the viewer's time zone, independent of location permission.
struct MoonCalendarMonth {
    struct Event {
        let quarter: MoonManager.Quarter
        let date: Date

        var name: String {
            switch quarter {
            case .newMoon: return String(localized: "moon.phase.new")
            case .firstQuarter: return String(localized: "moon.phase.waxing.first_quarter")
            case .fullMoon: return String(localized: "moon.phase.full")
            case .lastQuarter: return String(localized: "moon.phase.waning.last_quarter")
            }
        }
    }

    struct Day {
        let date: Date
        let gridIndex: Int
        let info: MoonManager.Info
        let illuminationChange: MoonManager.IlluminationChange
        let event: Event?

        var name: String { event?.name ?? info.name }
        var angle: Double { event?.quarter.rawValue ?? info.angle }
    }

    let start: Date
    let days: [Day]
    let events: [Event]
    let leadingEmptyDays: Int
    let nextFullMoon: Date
    let timeZone: TimeZone

    /// A failed calculation fails the snapshot; never fill missing days with estimates.
    /// Call off the main thread: quarter searches and daily phases use the ephemeris.
    static func calculate(containing date: Date, calendar: Calendar, now: Date = Date()) -> Self? {
        guard let interval = calendar.dateInterval(of: .month, for: date),
              let nextFullMoon = MoonManager.shared.nextOccurrence(of: .fullMoon, after: now) else { return nil }

        var events: [Event] = []
        for quarter in [MoonManager.Quarter.newMoon, .firstQuarter, .fullMoon, .lastQuarter] {
            var cursor = interval.start
            // A month can contain two occurrences of the same quarter.
            while cursor < interval.end {
                guard !Task.isCancelled,
                      let eventDate = MoonManager.shared.nextOccurrence(of: quarter, after: cursor),
                      eventDate >= cursor else { return nil }
                guard eventDate < interval.end else { break }
                events.append(Event(quarter: quarter, date: eventDate))
                cursor = eventDate.addingTimeInterval(1)
            }
        }
        events.sort { $0.date < $1.date }

        let leadingEmptyDays = (calendar.component(.weekday, from: interval.start) - calendar.firstWeekday + 7) % 7
        let firstDayNumber = calendar.component(.day, from: interval.start)
        var days: [Day] = []
        var day = interval.start
        while day < interval.end {
            guard !Task.isCancelled,
                  let dayInterval = calendar.dateInterval(of: .day, for: day),
                  dayInterval.end > day,
                  let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day),
                  let info = MoonManager.shared.info(at: noon),
                  let illuminationChange = MoonManager.shared.illuminationChange(during: dayInterval) else { return nil }
            let event = events.first { calendar.isDate($0.date, inSameDayAs: day) }
            // Leave a calendar cell empty when a time-zone change skipped a
            // whole civil date, rather than shifting all following weekdays.
            let gridIndex = leadingEmptyDays + calendar.component(.day, from: day) - firstDayNumber
            days.append(Day(date: day, gridIndex: gridIndex, info: info, illuminationChange: illuminationChange, event: event))
            day = dayInterval.end
        }
        return Self(start: interval.start, days: days, events: events,
                    leadingEmptyDays: leadingEmptyDays,
                    nextFullMoon: nextFullMoon, timeZone: calendar.timeZone)
    }
}
