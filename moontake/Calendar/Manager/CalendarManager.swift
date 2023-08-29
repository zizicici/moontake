//
//  CalendarManager.swift
//  lemon
//
//  Created by Ci Zi on 2023/5/28.
//

import Foundation
import UIKit
import OSLog

class CalendarManager {
    static let shared = CalendarManager()
    
    static let minYear: Int = 1899
    static let maxYear: Int = 2099
    
    private var chineseDataSources: [ChineseCalendarDataSource] = []
    private(set) var today: GregorianDay {
        didSet {
            if today != oldValue {
                NotificationCenter.default.post(Notification(name: Notification.Name.TodayUpdated))
            }
        }
    }
    
    let earlistYear = 1902
    let latestYear = 2098
    
    var moonPhasesCache: [Int: [(GregorianDay, MoonPhase)]] = [:]
    
    init() {
        let component = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: Date())
        self.today = GregorianDay(year: component.year ?? 1, month: Month(rawValue: component.month ?? 1) ?? .jan, day: component.day ?? 1)
        load(dataSourceName: "HKO1901_2099", variant: .chinese)
        load(dataSourceName: "kyureki", variant: .kyureki)
        NotificationCenter.default.addObserver(self, selector: #selector(updateToday), name: UIApplication.significantTimeChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateToday), name: UIApplication.didBecomeActiveNotification, object: nil)
    }
    
    func load(dataSourceName: String, variant: ChineseCalendarVariant) {
        if let url = Bundle.main.url(forResource: dataSourceName, withExtension: "json"), let data = try? Data(contentsOf: url) {
            do {
                var dataSource = try JSONDecoder().decode(ChineseCalendarDataSource.self, from: data)
                dataSource.variant = variant
                chineseDataSources.append(dataSource)
            } catch {
                print("Unexpected error: \(error).")
            }
        }
    }
    
    @objc
    func updateToday() {
        let component = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: Date())
        self.today = GregorianDay(year: component.year ?? 1, month: Month(rawValue: component.month ?? 1) ?? .jan, day: component.day ?? 1)
    }
    
    func getDays(in month: Month, year: Int) -> [GregorianDay] {
        let dayCount = dayCount(at: month, year: year)
        let result = Array(0..<dayCount).map { dayIndex in
            return GregorianDay(year: year, month: month, day: dayIndex + 1)
        }
        return result
    }
    
    func dayCount(at month: Month, isLeapYear: Bool) -> Int {
        switch month {
        case .jan, .mar, .may, .jul, .aug, .oct, .dec:
            return 31
        case .apr, .jun, .sep, .nov:
            return 30
        case .feb:
            return isLeapYear ? 29 : 28
        }
    }
    
    func dayCount(at month: Month, year: Int) -> Int {
        if year == 1582 && month == .oct {
            // 1582 fix
            return 21
        } else {
            return dayCount(at: month, isLeapYear: isLeap(year))
        }
    }
    
    func isLeap(_ year: Int) -> Bool {
        if year <= 4 {
            // Leap year error
            return fixLeap(year)
        } else {
            if year % 4 == 0 {
                if year > 1582 {
                    // Use Gregorian
                    if year % 100 == 0 {
                        return year % 400 == 0
                    } else {
                        return true
                    }
                } else {
                    return true
                }
            } else {
                return false
            }
        }
    }
    
    func fixLeap(_ year: Int) -> Bool {
        // Using Scaliger's theory
        if (year <= -8 && year >= -41) {
            return year % 3 == 2
        } else {
            return false
        }
    }
    
    func findChineseDayInfo(_ day: GregorianDay, variant: ChineseCalendarVariant) -> ChineseDayInfo? {
        let target = chineseDataSources.first { $0.variant == variant }
        return target?.findChineseDayInfo(day)
    }
    
    func firstDay(at month: Month, year: Int) -> Int {
        let day = GregorianDay(year: year, month: month, day: 1)
        return day.julianDay
    }
    
    func lastDay(at month: Month, year: Int) -> Int {
        let dayCount = dayCount(at: month, year: year)
        let day = GregorianDay(year: year, month: month, day: dayCount)
        return day.julianDay
    }
    
    func isToday(gregorianDay: GregorianDay?) -> Bool {
        if gregorianDay == nil {
            return false
        }
        return today == gregorianDay
    }
    
    func isCurrent(month: Month, year: Int) -> Bool {
        return (today.month == month) && (today.year == year)
    }
    
    func isCurrent(year: Int) -> Bool {
        return today.year == year
    }
    
    func nextMonth(month: Month, year: Int) -> (month: Month, year: Int)? {
        guard let nextMonth = Month(rawValue: (month.rawValue) % 12 + 1) else {
            return nil
        }
        
        switch month {
        case .dec:
            if year > latestYear {
                return nil
            }
            return (nextMonth, year + 1)
        default:
            return (nextMonth, year)
        }
    }
    
    func previousMonth(month: Month, year: Int) -> (month: Month, year: Int)? {
        guard let previousMonth = Month(rawValue: (month.rawValue + 10) % 12 + 1) else {
            return nil
        }
        
        switch month {
        case .jan:
            if year < earlistYear {
                return nil
            }
            return (previousMonth, year - 1)
        default:
            return (previousMonth, year)
        }
    }
    
    func getMoonPhase(at gregorianDay: GregorianDay) -> MoonPhase? {
        func loadMoonPhases(at year: Int) {
            os_log("start \(year)")
            if moonPhasesCache[year] == nil {
                moonPhasesCache[year] = AstronomyManager.shared.calculate(year: year).map { (GregorianDay(from: $0.date), $0) }
            }
            os_log("end \(year)")
        }
        func findFisrt(at year: Int, for gregorianDay: GregorianDay) -> MoonPhase? {
            return moonPhasesCache[year]?.first(where: { (day, moon) in
                return day == gregorianDay
            })?.1
        }
        
        var result: MoonPhase?
        loadMoonPhases(at: gregorianDay.year)
        result = findFisrt(at: gregorianDay.year, for: gregorianDay)
        
        if result == nil {
            if gregorianDay.month == .jan {
                loadMoonPhases(at: gregorianDay.year - 1)
                result = findFisrt(at: gregorianDay.year - 1, for: gregorianDay)
            } else if gregorianDay.month == .dec {
                loadMoonPhases(at: gregorianDay.year + 1)
                result = findFisrt(at: gregorianDay.year + 1, for: gregorianDay)
            }
        }

        return result
    }
    
    func isAvailable(day: GregorianDay) -> Bool {
        return isAvailable(year: day.year)
    }
    
    func isAvailable(year: Int) -> Bool {
        if year < CalendarManager.minYear || year > CalendarManager.maxYear {
            return false
        } else {
            return true
        }
    }
}
