import Foundation

enum AnyRange<Bound: Comparable> {
    case closed(ClosedRange<Bound>)
    case through(PartialRangeThrough<Bound>)
    case from(PartialRangeFrom<Bound>)

    var lowerBound: Bound? {
        switch self {
        case .closed(let range): return range.lowerBound
        case .through: return nil
        case .from(let range): return range.lowerBound
        }
    }

    var upperBound: Bound? {
        switch self {
        case .closed(let range): return range.upperBound
        case .through(let range): return range.upperBound
        case .from: return nil
        }
    }
}

extension AnyRange where Bound == Date {
    static func clamped(_ date: Date, to range: AnyRange<Date>?, calendar: Calendar) -> Date {
        guard let range = range else { return date }
        if range.contains(date, in: calendar) {
            return date
        }

        let day = calendar.startOfDay(for: date)
        if let lower = range.lowerBound {
            let lowerDay = calendar.startOfDay(for: lower)
            if day < lowerDay { return lowerDay }
        }

        if let upper = range.upperBound {
            let upperDay = calendar.startOfDay(for: upper)
            if day > upperDay { return upperDay }
        }

        return date
    }

    func contains(_ date: Date, in calendar: Calendar) -> Bool {
        let day = calendar.startOfDay(for: date)

        switch self {
        case .closed(let range):
            return day >= calendar.startOfDay(for: range.lowerBound) &&
                   day <= calendar.startOfDay(for: range.upperBound)
        case .through(let range):
            return day <= calendar.startOfDay(for: range.upperBound)
        case .from(let range):
            return day >= calendar.startOfDay(for: range.lowerBound)
        }
    }
}
