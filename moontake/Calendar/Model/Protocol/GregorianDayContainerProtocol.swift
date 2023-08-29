//
//  GregorianDayContainerProtocol.swift
//  totime
//
//  Created by Ci Zi on 2019/9/21.
//  Copyright © 2019 zizicici. All rights reserved.
//

import Foundation

protocol GregorianDayContainerProtocol {
    func firstDay() -> Int
    func lastDay() -> Int
}

extension GregorianDayContainerProtocol {
    func interSection(with other: GregorianDayContainerProtocol) -> Bool {
        return !(other.lastDay() < firstDay() || other.firstDay() > lastDay())
    }

    func contain(_ day: GregorianDay) -> Bool {
        return day.julianDay >= firstDay() && day.julianDay <= lastDay()
    }

    func earlier(than day: GregorianDay) -> Bool {
        return lastDay() < day.julianDay
    }
}

struct GregorianDayContainer: GregorianDayContainerProtocol {
    let start: GregorianDay
    let end: GregorianDay

    init(start: GregorianDay, end: GregorianDay) {
        self.start = start
        self.end = end
    }

    init(year: Int) {
        start = GregorianDay(year: year, month: .jan, day: 1)
        end = GregorianDay(year: year, month: .dec, day: 31)
    }

    init(year: Int, month: Month) {
        let dayCount = CalendarManager.shared.dayCount(at: month, year: year)
        start = GregorianDay(year: year, month: month, day: 1)
        end = GregorianDay(year: year, month: month, day: dayCount)
    }

    func firstDay() -> Int {
        return start.julianDay
    }

    func lastDay() -> Int {
        return end.julianDay
    }
}

extension Array where Element: GregorianDayContainerProtocol {
    func findElement(containing day: GregorianDay) -> Element? {
        var lowerBound: Int = 0
        var upperBound: Int = count
        while lowerBound < upperBound {
            let midIndex = lowerBound + (upperBound - lowerBound) / 2
            if self[midIndex].contain(day) {
                return self[midIndex]
            } else if self[midIndex].earlier(than: day) {
                lowerBound = midIndex + 1
            } else {
                upperBound = midIndex
            }
        }
        return nil
    }
}
