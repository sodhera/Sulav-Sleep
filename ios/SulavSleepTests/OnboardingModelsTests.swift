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
        // MARK: SleepDebt — the sign-up flow's arithmetic
        //
        // Every reveal screen reads off these, so the degenerate cases matter
        // as much as the typical one: a flow that divides by zero or claims a
        // shortfall against someone who sleeps eight hours loses the
        // credibility the whole arc runs on.

        // The recommendation floor is the *bottom* of the AASM band, never
        // its middle — the difference is ~50 nights a year in the hero figure.
        assert(SleepDebt.target == 420)
        assert(SleepDebt.recommendedRange == (420...540))

        // Typical: in bed 10:30pm, up 6:30am, an hour on the phone.
        let inBed = 22 * 60 + 30, wake = 6 * 60 + 30
        assert(SleepDebt.windowMinutes(inBed: inBed, wake: wake) == 480)
        assert(SleepDebt.derivedSleepMinutes(inBed: inBed, wake: wake, phone: 60) == 420)
        assert(SleepDebt.nightlyShortfall(sleepMinutes: 420) == 0)
        assert(SleepDebt.nightsShortPerYear(sleepMinutes: 420) == 0)
        assert(SleepDebt.phoneNightsPerYear(phone: 60) == 52)
        // The plan promises the whole window, and the gain it claims is
        // exactly the phone time — so the promise is retraceable by the user.
        assert(SleepDebt.protectedSleepMinutes(inBed: inBed, wake: wake) == 480)
        assert(SleepDebt.protectedSleepMinutes(inBed: inBed, wake: wake)
               - SleepDebt.derivedSleepMinutes(inBed: inBed, wake: wake, phone: 60) == 60)

        // Crosses midnight in the other direction (1am to 9am).
        assert(SleepDebt.windowMinutes(inBed: 60, wake: 9 * 60) == 480)

        // Already sleeping enough: no shortfall claimed, but the phone figure
        // still stands, so the centrepiece is never empty.
        assert(SleepDebt.nightlyShortfall(sleepMinutes: 450) == 0)
        assert(SleepDebt.nightsShortPerYear(sleepMinutes: 450) == 0)
        assert(SleepDebt.phoneNightsPerYear(phone: 15) == 13)

        // Nothing goes negative, and nothing exceeds the 4-hour phone ceiling.
        assert(SleepDebt.nightlyShortfall(sleepMinutes: -30) == 420)
        assert(SleepDebt.phoneNightsPerYear(phone: -30) == 0)
        assert(SleepDebt.phoneNightsPerYear(phone: 9_999) == SleepDebt.phoneNightsPerYear(phone: 240))
        // An out-of-range phone answer behaves as the 4-hour ceiling, so the
        // window keeps 480 - 240. It does not collapse to zero.
        assert(SleepDebt.derivedSleepMinutes(inBed: inBed, wake: wake, phone: 9_999) == 240)
        // A window shorter than the phone answer must clamp, not wrap.
        assert(SleepDebt.derivedSleepMinutes(inBed: 5 * 60, wake: 6 * 60, phone: 180) == 0)

        print("SleepDebt checks passed: floor, typical night, midnight wrap, no-shortfall case, clamps")
        print("Onboarding model checks passed: dial validation, estimates, profile round-trip, legacy values")
    }
}
