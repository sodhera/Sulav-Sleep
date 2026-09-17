import Foundation

@main
struct OnboardingModelsTests {
    static func main() throws {
        // Untouched and zero values must never silently accept the dial default.
        assert(!AttentionEstimate.isValid(minutes: 0, touched: false))
        assert(!AttentionEstimate.isValid(minutes: 0, touched: true))
        assert(!AttentionEstimate.isValid(minutes: 60, touched: false))
        assert(AttentionEstimate.isValid(minutes: 5, touched: true))
        assert(AttentionEstimate.isValid(minutes: 240, touched: true))
        assert(!AttentionEstimate.isValid(minutes: 241, touched: true))
        assert(AttentionEstimate.yearlyMinutes(60) == 21_900)
        assert(AttentionEstimate.lifetimeDays(60) == 1_216)
        assert(AttentionEstimate.yearlyMinutes(240) == 87_600)
        assert(AttentionEstimate.lifetimeDays(240) == 4_866)
        assert(AttentionEstimate.yearlyMinutes(-10) == 0)
        assert(AttentionEstimate.yearlyMinutes(300) == 87_600)

        let encoder = JSONEncoder(), decoder = JSONDecoder()
        // New raw values and exact minutes must survive the existing profile schema.
        let profile = Profile(name: "Test", bedtime: 1_350, wakeTime: 390, onboarded: true,
                              sleepStruggles: [SleepStruggle.negativeThoughts.rawValue],
                              primaryGoal: SleepGoal.lessPhoneAtNight.rawValue,
                              lateNightPhone: "minutes:95", wakeFeeling: WakeFeeling.calm.rawValue)
        let restored = try decoder.decode(Profile.self, from: encoder.encode(profile))
        assert(restored.lateNightPhone == "minutes:95")
        assert(restored.wakeFeeling == "calm")
        assert(restored.sleepStruggles == ["negativeThoughts"])
        // Existing accounts and drafts keep their historical enum representations.
        for value in LateNightPhoneTime.allCases {
            let decoded = try decoder.decode(LateNightPhoneTime.self, from: encoder.encode(value))
            assert(decoded == value)
        }
        for value in WakeFeeling.allCases {
            let decoded = try decoder.decode(WakeFeeling.self, from: encoder.encode(value))
            assert(decoded == value)
        }
        print("Onboarding model checks passed: dial validation, estimates, profile round-trip, legacy values")
    }
}
