import Foundation
import Testing
@testable import SulavSleep

struct SleepFormattingTests {
    @Test func durationFormatsHoursAndPaddedMinutes() {
        #expect(SleepFormatting.duration(430) == "7h 10m")
        #expect(SleepFormatting.duration(480) == "8h 00m")
        #expect(SleepFormatting.duration(65) == "1h 05m")
    }

    @Test func minutesAndDateRoundTrip() {
        let minutes = 6 * 60 + 45
        let date = SleepFormatting.date(fromMinutes: minutes)
        #expect(SleepFormatting.minutes(from: date) == minutes)
    }

    @Test func clockUsesTwelveHourFormat() {
        #expect(SleepFormatting.clock(0) == "12:00 AM")
        #expect(SleepFormatting.clock(13 * 60) == "1:00 PM")
        #expect(SleepFormatting.clock(22 * 60 + 30) == "10:30 PM")
    }
}
