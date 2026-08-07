import Foundation

// The App Group contract, shared by every process that touches the lockdown:
// the app, the DeviceActivityMonitor, and both shield extensions.
//
// **Foundation only, on purpose.** The shield configuration extension runs
// under a tight jetsam limit and a killed extension falls back to Apple's
// generic gray shield, so it must not link FamilyControls or DeviceActivity.
// That constraint used to be met by having each extension hardcode its own
// copy of the keys, which was survivable at five constants and a liability at
// twenty — a typo'd string is a silent no-op, not a build error. Everything
// framework-dependent (the `DeviceActivityName`s, the `FamilyActivitySelection`
// coding) stays in `SleepLockdownShared.swift`, which only the app and the
// monitor compile.

/// Which blocking phase is active, communicated via App Group UserDefaults so
/// the shield configuration and shield action extensions (which run in separate
/// sandboxed processes) can tailor their UI.
///
/// - `presleep`: Bedtime has arrived but the user hasn't tapped Sleep Now.
///   The shield nudges the user toward the app ("Time for bed — Sleep Now").
/// - `active`: The user tapped Sleep Now and a sleep session is running.
///   The shield is the firm lockdown ("Time to sleep — Good night").
///
/// Written by `ScreenTimeService` and `SulavSleepMonitor`; read by
/// `ShieldConfigProvider` and `ShieldActionHandler`.
enum LockdownPhase: String {
    case presleep
    case active
}

enum SleepLockdownSelection {
    /// Must match `SleepWidgetStore.appGroup`. Duplicated as a literal because
    /// that type lives in a file the shield extensions don't compile.
    static let appGroup = "group.com.sulav.sleepblock"

    static let selectionKey = "sulav.lock.selection.v1"
    /// App Group key for the current lockdown phase (see `LockdownPhase`).
    static let phaseKey = "sulav.lock.phase"

    static func groupDefaults() -> UserDefaults? {
        UserDefaults(suiteName: appGroup)
    }

    // MARK: - Phase helpers

    static func currentPhase() -> LockdownPhase? {
        guard let raw = groupDefaults()?.string(forKey: phaseKey) else { return nil }
        return LockdownPhase(rawValue: raw)
    }

    static func setPhase(_ phase: LockdownPhase) {
        groupDefaults()?.set(phase.rawValue, forKey: phaseKey)
    }

    static func clearPhase() {
        groupDefaults()?.removeObject(forKey: phaseKey)
    }

    // MARK: - Schedule mirror

    /// Bedtime as minutes-from-midnight, so the shield can place the user
    /// inside their own night. The shield extensions can't reach the app's
    /// profile, so the scheduler mirrors it here.
    static let bedtimeKey = "sulav.lock.bedtimeMinutes"
    /// Wake time, mirrored for the same reason. The shield leads with *time
    /// left until the alarm* rather than time past bedtime: one is a fact about
    /// the pain arriving in the morning, the other is a scolding about a
    /// decision already made, and only the first is worth a bold title.
    static let wakeKey = "sulav.lock.wakeMinutes"

    static func setBedtimeMinutes(_ minutes: Int) {
        groupDefaults()?.set(minutes, forKey: bedtimeKey)
    }

    static func bedtimeMinutes() -> Int? {
        groupDefaults()?.object(forKey: bedtimeKey) as? Int
    }

    static func setWakeMinutes(_ minutes: Int) {
        groupDefaults()?.set(minutes, forKey: wakeKey)
    }

    static func wakeMinutes() -> Int? {
        groupDefaults()?.object(forKey: wakeKey) as? Int
    }

    /// Minutes from `now` until the next occurrence of `wakeMinutes`. Nil when
    /// wake time isn't mirrored yet. Always positive — a wake time already
    /// passed today means tomorrow's alarm.
    static func minutesUntilWake(now: Date = Date(), calendar: Calendar = .current) -> Int? {
        guard let wake = wakeMinutes() else { return nil }
        let components = calendar.dateComponents([.hour, .minute], from: now)
        let minutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        var delta = wake - minutes
        if delta <= 0 { delta += 1_440 }
        return delta
    }

    // MARK: - Snooze ("5 more minutes")

    /// When the current snooze expires (`timeIntervalSince1970`). Absent when
    /// no snooze is running.
    static let snoozeUntilKey = "sulav.lock.snoozeUntil"
    /// Snoozes already spent in this lockdown window.
    static let snoozeCountKey = "sulav.lock.snoozeCount"
    /// Which lockdown window the spent-snooze count belongs to, stored as that
    /// window's start (`timeIntervalSince1970`). See `beginWindowIfNew`.
    static let snoozeWindowKey = "sulav.lock.snoozeWindowStart"

    /// Minutes granted per snooze, and how many a single lockdown window
    /// allows. Capped because an uncapped snooze is an off switch with extra
    /// steps — the whole point is that the escape hatch runs out.
    static let snoozeMinutes = 5
    static let snoozeLimit = 2

    static func snoozesSpent() -> Int {
        groupDefaults()?.integer(forKey: snoozeCountKey) ?? 0
    }

    /// Hard mode removes the snooze entirely — that is most of what the user
    /// bought when they chose it.
    static var snoozeAvailable: Bool { !hardMode() && snoozesSpent() < snoozeLimit }

    /// Spends one snooze and returns when it expires. Caller is responsible
    /// for actually lifting the shield and arranging the re-arm.
    @discardableResult
    static func consumeSnooze(now: Date = Date()) -> Date {
        let until = now.addingTimeInterval(Double(snoozeMinutes) * 60)
        groupDefaults()?.set(snoozesSpent() + 1, forKey: snoozeCountKey)
        groupDefaults()?.set(until.timeIntervalSince1970, forKey: snoozeUntilKey)
        return until
    }

    static func snoozeUntil() -> Date? {
        guard let raw = groupDefaults()?.object(forKey: snoozeUntilKey) as? Double else { return nil }
        return Date(timeIntervalSince1970: raw)
    }

    /// True when a snooze was granted and its time is up — the shield should
    /// be back on. Checked defensively by the app and the monitor, because the
    /// timed re-arm is the least reliable link in the chain.
    static func snoozeHasExpired(now: Date = Date()) -> Bool {
        guard let until = snoozeUntil() else { return false }
        return now >= until
    }

    /// Ends the current snooze without touching the spent count.
    static func clearSnoozeWindow() {
        groupDefaults()?.removeObject(forKey: snoozeUntilKey)
    }

    /// Fresh allowance, unconditionally. Correct at the *end* of a window,
    /// where the next one should start clean. To open a window, prefer
    /// `beginWindowIfNew()`, which won't hand out a second allowance for a
    /// night that already had one.
    static func resetSnoozes() {
        groupDefaults()?.removeObject(forKey: snoozeCountKey)
        groupDefaults()?.removeObject(forKey: snoozeWindowKey)
        clearSnoozeWindow()
    }

    // MARK: - Window math

    /// Start of the lockdown window containing `now`: today's bedtime if it has
    /// already passed, otherwise yesterday's. The look-back is what keeps the
    /// answer stable across midnight — at 01:00 under a 23:00 bedtime, the
    /// window in force started at 23:00 *yesterday*, and calling it "today's"
    /// would make one night look like two.
    static func windowStart(now: Date = Date(),
                            bedtimeMinutes: Int,
                            calendar: Calendar = .current) -> Date? {
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = (bedtimeMinutes / 60) % 24
        components.minute = bedtimeMinutes % 60
        components.second = 0
        guard let todays = calendar.date(from: components) else { return nil }
        return todays <= now ? todays : calendar.date(byAdding: .day, value: -1, to: todays)
    }

    /// Whether `now` falls inside a bedtime→wake window, handling the usual
    /// case where it crosses midnight.
    static func isWithinWindow(now: Date = Date(),
                               bedtimeMinutes: Int,
                               wakeMinutes: Int,
                               calendar: Calendar = .current) -> Bool {
        // A zero-length window blocks nothing; treating it as "always inside"
        // would wedge the schedule permanently.
        guard bedtimeMinutes != wakeMinutes else { return false }
        let components = calendar.dateComponents([.hour, .minute], from: now)
        let minutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        return bedtimeMinutes < wakeMinutes
            ? (minutes >= bedtimeMinutes && minutes < wakeMinutes)
            : (minutes >= bedtimeMinutes || minutes < wakeMinutes)
    }

    /// Opens a genuinely new night's bookkeeping: a fresh snooze allowance, an
    /// empty reach log, and a shut door.
    ///
    /// Guarded by the window's start date rather than by the fact of
    /// `intervalDidStart` firing, because that callback is not once-per-night:
    /// re-registering `sleepActivityName` while its interval is already running
    /// fires it again. That made an unlimited snooze supply reachable from the
    /// UI — edit the schedule by a minute, save, collect two more "5 more
    /// minutes", repeat. `SleepStore.rescheduleLockdown` now refuses to
    /// re-register mid-window, and this is the second lock on the same door:
    /// however the callback arrives, a night gets one allowance.
    ///
    /// The reach log is cleared *here*, at the window's start, and deliberately
    /// not when it ends — the morning mirror reads the night's log long after
    /// the shield is gone.
    ///
    /// Without a mirrored bedtime there is no window to identify, so this falls
    /// back to resetting — the same behaviour as before, and the forgiving
    /// direction to fail in.
    @discardableResult
    static func beginWindowIfNew(now: Date = Date()) -> Bool {
        guard let bedtime = bedtimeMinutes(),
              let start = windowStart(now: now, bedtimeMinutes: bedtime)
        else {
            openWindowBookkeeping()
            return true
        }
        let stamp = start.timeIntervalSince1970
        if let previous = groupDefaults()?.object(forKey: snoozeWindowKey) as? Double,
           abs(previous - stamp) < 1 {
            return false  // same night, allowance already issued
        }
        openWindowBookkeeping()
        groupDefaults()?.set(stamp, forKey: snoozeWindowKey)
        return true
    }

    private static func openWindowBookkeeping() {
        resetSnoozes()
        clearReachLog()
        clearDoor()
    }

    // MARK: - The user's own words

    /// The reasons the user wrote for wanting this, mirrored for the shield.
    ///
    /// The shield argues with someone at 1am, and the app's own copy is the
    /// weakest possible voice for that job — it reads as one more piece of
    /// software telling them what to do. Their own sentence is much harder to
    /// dismiss, because there is nobody to be annoyed at.
    ///
    /// A list, not one string, and rotated per reach (see `reasonForReach`): a
    /// single line stops being visible after about a week, the same way a
    /// desktop wallpaper does. Rotating keeps it readable rather than furniture.
    static let reasonsKey = "sulav.lock.reasons"

    /// How many reasons a user may write. Enough to rotate, few enough that
    /// each one stays considered.
    static let reasonLimit = 3
    /// Character ceiling on a single reason. The shield's subtitle is one short
    /// line — longer text wraps badly or truncates — and the constraint makes
    /// people write the true thing instead of a slogan.
    static let reasonMaxLength = 60

    static func setReasons(_ reasons: [String]) {
        groupDefaults()?.set(reasons, forKey: reasonsKey)
    }

    static func reasons() -> [String] {
        groupDefaults()?.stringArray(forKey: reasonsKey) ?? []
    }

    /// The reason to show on the `n`th reach of the night, rotating so a user
    /// who keeps trying meets a different sentence each time. Nil when they
    /// haven't written any.
    static func reasonForReach(_ n: Int) -> String? {
        let all = reasons()
        guard !all.isEmpty else { return nil }
        return all[max(0, n - 1) % all.count]
    }

    // MARK: - Reach attempts

    /// Every time the user opens a blocked app, as `timeIntervalSince1970`.
    ///
    /// The most valuable data the app has, and it costs nothing to collect: the
    /// shield configuration extension is asked for a fresh configuration on
    /// each attempt, so the count falls out of a screen that has to render
    /// anyway. Read back in the morning as a plain mirror — never a scolding.
    static let reachLogKey = "sulav.lock.reachLog"

    /// Attempts closer together than this are one reach. The system can ask for
    /// a shield configuration more than once for a single app launch, and an
    /// inflated count would make the morning mirror a lie.
    static let reachDebounce: TimeInterval = 5

    /// A night's worth of reaches is bounded — someone hammering an app should
    /// not be able to grow this array without limit inside a jetsam-constrained
    /// extension.
    static let reachLogLimit = 500

    static func reachLog() -> [Date] {
        let raw = groupDefaults()?.array(forKey: reachLogKey) as? [Double] ?? []
        return raw.map { Date(timeIntervalSince1970: $0) }
    }

    static func reachCount() -> Int {
        (groupDefaults()?.array(forKey: reachLogKey) as? [Double])?.count ?? 0
    }

    /// Records one reach, debounced. Returns the running count so a caller that
    /// is already rendering (the shield) can rotate the reason without a second
    /// read.
    @discardableResult
    static func recordReach(now: Date = Date()) -> Int {
        guard let defaults = groupDefaults() else { return 0 }
        var log = defaults.array(forKey: reachLogKey) as? [Double] ?? []
        let stamp = now.timeIntervalSince1970
        if let last = log.last, stamp - last < reachDebounce { return log.count }
        log.append(stamp)
        if log.count > reachLogLimit { log.removeFirst(log.count - reachLogLimit) }
        defaults.set(log, forKey: reachLogKey)
        return log.count
    }

    /// Cleared when a window *opens*, never when it closes — the morning mirror
    /// reads the night's log after the shield is already gone.
    static func clearReachLog() {
        groupDefaults()?.removeObject(forKey: reachLogKey)
    }

    /// Leaves behind only the attempts the app hasn't filed yet — the tail
    /// belonging to a window that is still running. See
    /// `SleepStore.harvestReachLog`.
    static func replaceReachLog(with attempts: [Date]) {
        groupDefaults()?.set(attempts.map(\.timeIntervalSince1970), forKey: reachLogKey)
    }

    // MARK: - The slow door

    /// An always-available exit that costs time rather than being refused.
    ///
    /// Deleting SleepBlock is itself an escape hatch, and the only one that
    /// can't be taken away. A lockdown whose sole remaining exits are "wait
    /// until morning" and "delete the app" pushes people toward the permanent
    /// one, so the door exists to be *taken* — it is retention, not leniency.
    ///
    /// It costs a wait, because a craving fades in about a minute: the first
    /// tap only writes `doorRequestedKey`, and the shield the user meets on
    /// their next attempt is the one that opens. Most people put the phone down
    /// during the wait; the ones who don't get their minutes and keep the app.
    ///
    /// The two-step shape is also what makes it *implementable*: a shield
    /// action extension is torn down the instant it answers a tap and can't run
    /// a timer, but the shield is re-rendered on every attempt, so the user's
    /// own second attempt is the clock.
    static let doorRequestedKey = "sulav.lock.doorRequestedAt"
    static let doorOpenUntilKey = "sulav.lock.doorOpenUntil"

    /// How long the user waits before the door opens, and how long it stays
    /// open. `hardMode` triples the wait — chosen strictness, not imposed.
    static let doorWaitSeconds: TimeInterval = 60
    static let doorHardWaitSeconds: TimeInterval = 180
    static let doorMinutes = 10

    static let hardModeKey = "sulav.lock.hardMode"

    static func setHardMode(_ on: Bool) {
        groupDefaults()?.set(on, forKey: hardModeKey)
    }

    static func hardMode() -> Bool {
        groupDefaults()?.bool(forKey: hardModeKey) ?? false
    }

    static var doorWait: TimeInterval { hardMode() ? doorHardWaitSeconds : doorWaitSeconds }

    /// When the user asked for the door, if they have.
    static func doorRequestedAt() -> Date? {
        guard let raw = groupDefaults()?.object(forKey: doorRequestedKey) as? Double else { return nil }
        return Date(timeIntervalSince1970: raw)
    }

    static func requestDoor(now: Date = Date()) {
        groupDefaults()?.set(now.timeIntervalSince1970, forKey: doorRequestedKey)
    }

    /// Seconds still to wait, or nil when no request is outstanding. Zero means
    /// the wait is served and the next tap opens the door.
    static func doorSecondsRemaining(now: Date = Date()) -> TimeInterval? {
        guard let requested = doorRequestedAt() else { return nil }
        return max(0, doorWait - now.timeIntervalSince(requested))
    }

    /// Spends the wait and opens the door. Caller lifts the shield.
    @discardableResult
    static func openDoor(now: Date = Date()) -> Date {
        let until = now.addingTimeInterval(Double(doorMinutes) * 60)
        groupDefaults()?.set(until.timeIntervalSince1970, forKey: doorOpenUntilKey)
        groupDefaults()?.removeObject(forKey: doorRequestedKey)
        return until
    }

    static func doorOpenUntil() -> Date? {
        guard let raw = groupDefaults()?.object(forKey: doorOpenUntilKey) as? Double else { return nil }
        return Date(timeIntervalSince1970: raw)
    }

    /// True when the door was opened and its time is up — the shield belongs
    /// back. Mirrors `snoozeHasExpired`, and is checked by the same layers.
    static func doorHasExpired(now: Date = Date()) -> Bool {
        guard let until = doorOpenUntil() else { return false }
        return now >= until
    }

    static func clearDoor() {
        groupDefaults()?.removeObject(forKey: doorRequestedKey)
        groupDefaults()?.removeObject(forKey: doorOpenUntilKey)
    }

    // MARK: - What the shield offers next

    /// The single escape the shield should present, resolved in one place so
    /// the configuration extension (which draws the button) and the action
    /// extension (which answers the tap) cannot disagree about what it means.
    enum Escape: Equatable {
        /// Presleep, snoozes left, not hard mode.
        case snooze
        /// Nothing outstanding — offer the door.
        case doorClosed
        /// Asked for, still waiting. Informational; tapping does nothing.
        case doorWaiting(seconds: Int)
        /// The wait is served; the next tap opens it.
        case doorReady
    }

    static func currentEscape(now: Date = Date()) -> Escape {
        if let remaining = doorSecondsRemaining(now: now) {
            return remaining > 0 ? .doorWaiting(seconds: Int(remaining.rounded(.up))) : .doorReady
        }
        // The snooze is presleep-only: it is a nudge for someone who hasn't
        // committed yet. Once they've tapped Sleep Now the door is the only
        // exit, and it costs the wait.
        if currentPhase() == .presleep, snoozeAvailable { return .snooze }
        return .doorClosed
    }
}
