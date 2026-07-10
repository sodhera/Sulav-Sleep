import Foundation
import HealthKit

// MARK: - Pure night grouping (unit-testable, no HealthKit dependency)

/// A raw "asleep" interval, e.g. one segment reported by Apple Watch.
struct SleepInterval: Equatable {
    var start: Date
    var end: Date

    var minutes: Int { max(0, Int(end.timeIntervalSince(start) / 60)) }
}

/// Turns a flat list of asleep intervals into per-night `SleepSession`s.
///
/// Apple Health returns sleep as many short segments (core / deep / REM), often
/// overlapping or adjacent. We group segments into nights on large gaps, then
/// compute each night's real asleep time as the *union* of its segments so
/// overlaps are never double counted. This is the core of "no dummy data": the
/// numbers come straight from the user's own Health samples.
enum SleepNightBuilder {
    /// A gap larger than this between segments starts a new night.
    static let nightGapThreshold: TimeInterval = 3 * 3600
    /// Ignore groups shorter than this so daytime naps don't masquerade as nights.
    static let minimumNightMinutes = 45

    static func nights(from intervals: [SleepInterval], targetMinutes: Int, now: Date = Date()) -> [SleepSession] {
        let sorted = intervals
            .filter { $0.end > $0.start }
            .sorted { $0.start < $1.start }
        guard !sorted.isEmpty else { return [] }

        var groups: [[SleepInterval]] = []
        var current: [SleepInterval] = []
        var lastEnd: Date?
        for interval in sorted {
            if let lastEnd, interval.start.timeIntervalSince(lastEnd) > nightGapThreshold {
                groups.append(current)
                current = []
            }
            current.append(interval)
            lastEnd = max(lastEnd ?? interval.end, interval.end)
        }
        if !current.isEmpty { groups.append(current) }

        return groups.compactMap { group -> SleepSession? in
            let minutes = unionMinutes(of: group)
            guard minutes >= minimumNightMinutes else { return nil }
            let start = group.map(\.start).min() ?? now
            let end = group.map(\.end).max() ?? now
            return SleepSession(
                id: "hk-\(Int(end.timeIntervalSince1970))",
                start: start,
                end: end,
                durationMinutes: minutes,
                source: .healthKit
            )
        }
        .sorted { $0.end < $1.end }
    }

    /// Total covered minutes across intervals, merging overlaps.
    static func unionMinutes(of intervals: [SleepInterval]) -> Int {
        let sorted = intervals.sorted { $0.start < $1.start }
        var total: TimeInterval = 0
        var curStart: Date?
        var curEnd: Date?
        for iv in sorted {
            if let start = curStart, let end = curEnd {
                if iv.start <= end {
                    curEnd = max(end, iv.end)
                } else {
                    total += end.timeIntervalSince(start)
                    curStart = iv.start
                    curEnd = iv.end
                }
            } else {
                curStart = iv.start
                curEnd = iv.end
            }
        }
        if let start = curStart, let end = curEnd {
            total += end.timeIntervalSince(start)
        }
        return Int(total / 60)
    }
}

// MARK: - Provider protocol (so the store can be tested with a mock)

protocol SleepHealthProviding {
    var isAvailable: Bool { get }
    /// True once the user has explicitly denied access (so re-requesting would
    /// no-op and the app should send them to Settings instead of re-prompting).
    var isAccessDenied: Bool { get }
    func requestAuthorization() async -> Bool
    func fetchNights(days: Int, targetMinutes: Int) async -> [SleepSession]
    func save(session: SleepSession) async
}

enum SleepHealth {
    /// Returns the real HealthKit provider when the device supports it, otherwise
    /// a no-op so the rest of the app is oblivious to platform availability.
    static func makeDefault() -> SleepHealthProviding {
        HKHealthStore.isHealthDataAvailable() ? HealthKitService() : DisabledHealthService()
    }
}

/// No-op provider used when HealthKit is unavailable or for previews.
struct DisabledHealthService: SleepHealthProviding {
    var isAvailable: Bool { false }
    var isAccessDenied: Bool { false }
    func requestAuthorization() async -> Bool { false }
    func fetchNights(days: Int, targetMinutes: Int) async -> [SleepSession] { [] }
    func save(session: SleepSession) async {}
}

// MARK: - Real HealthKit implementation

final class HealthKitService: SleepHealthProviding {
    private let store = HKHealthStore()
    private let sleepType = HKCategoryType(.sleepAnalysis)

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// HealthKit hides *read* authorization for privacy, but exposes *share*
    /// (write) status — and our two-way sync writes logged nights to Health, so
    /// write access is genuinely required for a connection to mean anything.
    /// A `.sharingDenied` here is the reliable "user said no" signal.
    var isAccessDenied: Bool {
        guard isAvailable else { return false }
        return store.authorizationStatus(for: sleepType) == .sharingDenied
    }

    func requestAuthorization() async -> Bool {
        guard isAvailable else { return false }
        let types: Set<HKSampleType> = [sleepType]
        do {
            try await store.requestAuthorization(toShare: types, read: types)
            // `requestAuthorization` succeeds merely for *showing* the sheet — it
            // returns without error even when the user taps "Don't Allow", and
            // never reveals read grants. So don't treat a clean return as
            // connected; check the share status, which does reflect the choice.
            let status = store.authorizationStatus(for: sleepType)
            let authorized = status == .sharingAuthorized
            AppLog.health.info("HealthKit sleep authorization status=\(status.rawValue) authorized=\(authorized)")
            return authorized
        } catch {
            AppLog.health.error("HealthKit authorization failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func fetchNights(days: Int, targetMinutes: Int) async -> [SleepSession] {
        guard isAvailable else { return [] }
        return await AppSignpost.health.measure("ImportHealthKit") {
            let intervals = await fetchAsleepIntervals(days: days)
            let nights = SleepNightBuilder.nights(from: intervals, targetMinutes: targetMinutes)
            AppLog.health.info("Imported \(nights.count) night(s) from Health over \(days)d")
            return nights
        }
    }

    func save(session: SleepSession) async {
        guard isAvailable else { return }
        let sample = HKCategorySample(
            type: sleepType,
            value: HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            start: session.start,
            end: session.end
        )
        do {
            try await store.save(sample)
            AppLog.health.info("Saved \(session.durationMinutes)m night to Health")
        } catch {
            AppLog.health.error("HealthKit save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func fetchAsleepIntervals(days: Int) async -> [SleepInterval] {
        let start = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: sort
            ) { _, samples, error in
                guard error == nil, let samples = samples as? [HKCategorySample] else {
                    if let error { AppLog.health.error("HealthKit query failed: \(error.localizedDescription, privacy: .public)") }
                    continuation.resume(returning: [])
                    return
                }
                let intervals = samples
                    .filter { Self.isAsleep($0.value) }
                    .map { SleepInterval(start: $0.startDate, end: $0.endDate) }
                continuation.resume(returning: intervals)
            }
            store.execute(query)
        }
    }

    private static func isAsleep(_ value: Int) -> Bool {
        switch value {
        case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
             HKCategoryValueSleepAnalysis.asleepCore.rawValue,
             HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
             HKCategoryValueSleepAnalysis.asleepREM.rawValue:
            return true
        default:
            return false
        }
    }
}
