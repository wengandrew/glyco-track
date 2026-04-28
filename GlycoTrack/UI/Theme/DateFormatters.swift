import Foundation

/// Shared cached `DateFormatter` instances. Centralized so:
///   1. We don't pay repeated allocation cost during SwiftUI updates.
///   2. The format strings live in one place — easier to keep date displays
///      visually consistent across tabs.
extension DateFormatter {
    /// "Mon, Apr 27" — short title-bar / heading form.
    static let short: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f
    }()

    /// "Monday, Apr 27" — full weekday form, used in date subheadings.
    static let weekdayMonthDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f
    }()

    /// "Apr 27" — compact day-only form, used in week-range strings.
    static let monthDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    /// "04/27/2026" — numeric form used in list rows.
    static let numericMonthDayYear: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM/dd/yyyy"
        return f
    }()
}
