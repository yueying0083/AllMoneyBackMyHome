import Foundation

public struct MarketSchedule: Sendable {
    public var calendar: Calendar

    public init() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        self.calendar = calendar
    }

    public init(calendar: Calendar) {
        self.calendar = calendar
    }

    public func isTradingTime(_ date: Date) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        guard (2...6).contains(weekday) else { return false }
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let value = hour * 60 + minute
        return (570...690).contains(value) || (780...900).contains(value)
    }
}
