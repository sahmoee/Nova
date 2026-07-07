//
//  DateFormatting.swift
//  Astra
//
//  Shared, cached date formatters. DateFormatter is relatively expensive to
//  create, and the same two styles were being rebuilt inline in several views.
//  Centralizing them keeps formatting consistent and avoids the repeated setup.
//

import Foundation

extension Date {
    /// Medium date, no time — e.g. "Jan 5, 2026". Used for air dates and similar.
    var mediumDateText: String { AstraDateFormatters.mediumDate.string(from: self) }

    /// Medium date with short time — e.g. "Jan 5, 2026 at 3:30 PM". Used for
    /// "last backed up" / snapshot timestamps.
    var mediumDateTimeText: String { AstraDateFormatters.mediumDateTime.string(from: self) }
}

/// Cached formatter instances shared across the app.
enum AstraDateFormatters {
    static let mediumDate: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()

    static let mediumDateTime: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}
