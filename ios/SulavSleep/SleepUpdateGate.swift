import SwiftUI
#if canImport(Supabase)
import Supabase
#endif

// The app update gate: server-driven version handling, the way production
// apps (Spotify, banking apps) do it. One remote-config row per platform
// (`app_config`, migration 004) carries two thresholds the client compares
// its own version against on launch and foreground:
//
//   * installed < `min_supported_version` → **forced gate**: a full-screen,
//     non-dismissible "update required" (`UpdateRequiredView`, mounted by
//     RootView). Reserved for releases where old clients are actually broken
//     — the app is schema-coupled to Supabase now (the feature board hard-
//     fails when the client's column list runs ahead of the migrations), and
//     without this gate a stranded old client just shows broken screens with
//     no way to tell the user why.
//   * installed < `latest_version` → **soft nudge**: a quiet, dismissible
//     card on Profile (`UpdateNudgeCard`), once per version. The old build
//     still works; this is awareness, not a wall.
//
// Golden rules, all load-bearing:
//   * **Fail open.** A missed fetch, a missing row, or a bad version string
//     never blocks anyone — a network hiccup is not an outdated app.
//   * **The gate never outranks sleep mode.** An active night keeps
//     wake/cancel (and the lockdown teardown) reachable, same as the
//     paywall's rule in RootView.
//   * **Never bump `min_supported_version` before the new build is live** on
//     the App Store — a gate whose Update button installs nothing is a trap.
//     Release checklist in docs/development.md.
//
// Everything for the feature lives in this one file (version compare, config
// row, network protocol + factory + stub, store logic, both views), the same
// way SleepScreenTime.swift and SleepFeatureRequests.swift keep theirs.

// MARK: - Version compare

/// Dotted-numeric version handling ("1.0" < "1.2.3"). Component-wise integer
/// compare; missing components read as 0, non-numeric components as 0 (so a
/// malformed server value like "abc" compares as 0.0.0 and blocks nobody —
/// fail open extends to parsing).
enum AppVersion {
    /// The installed marketing version (CFBundleShortVersionString).
    static var installed: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    static func isOlder(_ lhs: String, than rhs: String) -> Bool {
        let a = components(lhs)
        let b = components(rhs)
        for index in 0 ..< max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            if x != y { return x < y }
        }
        return false
    }

    private static func components(_ version: String) -> [Int] {
        version.split(separator: ".").map { Int($0) ?? 0 }
    }
}

// MARK: - Config row

struct AppUpdateConfig: Decodable, Equatable, Sendable {
    let minSupportedVersion: String
    let latestVersion: String
    let updateMessage: String?

    enum CodingKeys: String, CodingKey {
        case minSupportedVersion = "min_supported_version"
        case latestVersion = "latest_version"
        case updateMessage = "update_message"
    }
}

// MARK: - Checking protocol (testable)

/// Returns nil on any failure — the caller treats nil as "no new
/// information", never as "blocked". This is the fail-open property.
protocol UpdateGateChecking: Sendable {
    func fetchConfig() async -> AppUpdateConfig?
}

enum UpdateGateService {
    /// Mirrors `SleepCloud`/`FeatureRequestBoard`: real service when the
    /// shared Supabase client exists, inert stub otherwise.
    static func makeDefault() -> UpdateGateChecking {
        #if canImport(Supabase)
        guard let client = SulavAuth.sharedClient else { return DisabledUpdateGate() }
        return SupabaseUpdateGate(client: client)
        #else
        return DisabledUpdateGate()
        #endif
    }
}

struct DisabledUpdateGate: UpdateGateChecking {
    func fetchConfig() async -> AppUpdateConfig? { nil }
}

#if canImport(Supabase)

final class SupabaseUpdateGate: UpdateGateChecking, @unchecked Sendable {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func fetchConfig() async -> AppUpdateConfig? {
        do {
            let rows: [AppUpdateConfig] = try await client
                .from("app_config")
                .select("min_supported_version,latest_version,update_message")
                .eq("platform", value: "ios")
                .limit(1)
                .execute()
                .value
            return rows.first
        } catch {
            // Fail open: log and report nothing.
            AppLog.app.error("Update gate: config fetch failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

#endif

// MARK: - Store logic

/// State lives as stored properties on `SleepStore` (extensions can't add
/// storage); everything that *decides* lives here.
extension SleepStore {
    /// Fetch the config and update the gate/nudge state. Called from the app
    /// launch task and every foreground activation (AppDelegate). Throttled
    /// in-memory to once an hour — which also means a cold launch always
    /// checks, no persistence needed — except while the gate is up, when
    /// every foreground re-checks so a server-side revert (a mistaken bump,
    /// fixed in the SQL editor) lifts the gate without a reinstall.
    func checkAppUpdateGate() async {
        // No store id → the gate's Update button would have nowhere to go,
        // and a blocking screen with a dead button is worse than no gate.
        guard AppStoreLink.isConfigured else { return }
        if !updateRequired,
           let last = lastUpdateGateCheck,
           Date().timeIntervalSince(last) < 3600 {
            return
        }

        guard let config = await UpdateGateService.makeDefault().fetchConfig() else { return }
        lastUpdateGateCheck = Date()

        let installed = AppVersion.installed
        updateRequired = AppVersion.isOlder(installed, than: config.minSupportedVersion)
        updateGateMessage = config.updateMessage
        availableUpdateVersion = AppVersion.isOlder(installed, than: config.latestVersion)
            ? config.latestVersion
            : nil
        dismissedUpdateNudgeVersion = SleepPersistence.shared.dismissedUpdateNudgeVersion

        if updateRequired {
            AppLog.app.notice("Update gate: \(installed, privacy: .public) < min \(config.minSupportedVersion, privacy: .public) — blocking")
        } else {
            AppLog.app.info("Update gate: \(installed, privacy: .public) ok (min \(config.minSupportedVersion, privacy: .public))")
        }
    }

    /// The Profile nudge: a newer build exists, this one still works, and the
    /// user hasn't waved *this* version away. The forced gate suppresses it
    /// by construction (the gate covers the whole screen).
    var shouldShowUpdateNudge: Bool {
        guard !updateRequired, let version = availableUpdateVersion else { return false }
        return dismissedUpdateNudgeVersion != version
    }

    /// Per-version dismissal: waving off 1.2 stays waved off for every 1.2
    /// check, but 1.3 asks once again. Survives `reset()` — signing out is
    /// not a reason to re-nudge.
    func dismissUpdateNudge() {
        guard let version = availableUpdateVersion else { return }
        SleepPersistence.shared.dismissUpdateNudge(version: version)
        dismissedUpdateNudgeVersion = version
        AppLog.app.info("Update nudge dismissed for \(version, privacy: .public)")
    }

    /// Opens the plain App Store product page (no review sheet) — the
    /// destination of both the gate's and the nudge's Update button.
    func openAppStoreProductPage() {
        #if canImport(UIKit)
        guard let url = AppStoreLink.productPage else { return }
        UIApplication.shared.open(url)
        #endif
    }
}

// MARK: - Forced gate screen

/// The blocking "update required" screen, mounted by RootView beneath sleep
/// mode and above everything else. Same scene grammar as the other root
/// gates (onboarding, paywall, primer): the night city, a scrim, the brand
/// sloth, an editorial title, one primary action. Deliberately no dismiss,
/// no "later", no fine print — by the time this shows, the app on this
/// device doesn't work, and the only honest affordance is the fix.
struct UpdateRequiredView: View {
    /// Server-set copy (`app_config.update_message`), so the *reason* can be
    /// stated without shipping an app release. Falls back to a generic line.
    var message: String?
    var onUpdate: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            SlothBrandMark(width: SlothBrandMark.heroWidth, zScale: SlothBrandMark.heroZScale)

            Text("Time to update")
                .font(SleepFont.hero(28))
                .foregroundStyle(SleepColor.ink)
                .padding(.top, SleepSpacing.xxl)

            Text(message ?? "This version of SleepBlock can't talk to the server anymore. Update to keep your sleep record in sync.")
                .font(SleepFont.body(15))
                .foregroundStyle(SleepColor.dim)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, SleepSpacing.md)

            Spacer()

            LiquidPrimaryButton(title: "Update SleepBlock") {
                onUpdate()
            }
            .padding(.bottom, SleepSpacing.huge)
        }
        .padding(.horizontal, SleepSpacing.xxl)
    }
}

// MARK: - Soft nudge card

/// The Profile "update available" card — the same dismissible-card grammar
/// as `HealthConnectCard` (warm glyph, title + one line, a capsule action,
/// a quiet ✕), because Profile already taught the user what that shape
/// means: an invitation, not an obligation.
struct UpdateNudgeCard: View {
    let version: String
    var onUpdate: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: SleepSpacing.md) {
            Image(systemName: "arrow.down.app.fill")
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(SleepColor.amber)

            VStack(alignment: .leading, spacing: SleepSpacing.sm) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Update available")
                        .font(SleepFont.title(16))
                        .foregroundStyle(SleepColor.ink)
                    Text("SleepBlock \(version) is on the App Store.")
                        .font(SleepFont.body(13))
                        .foregroundStyle(SleepColor.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    Haptics.heavy()
                    onUpdate()
                } label: {
                    Text("Update")
                        .font(SleepFont.label(14))
                        .foregroundStyle(SleepColor.background)
                        .padding(.horizontal, SleepSpacing.lg)
                        .padding(.vertical, SleepSpacing.sm)
                        .background {
                            Capsule(style: .continuous)
                                .fill(LinearGradient(
                                    colors: [SleepColor.gold, SleepColor.amber],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                ))
                        }
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }

            Spacer(minLength: 0)

            Button {
                Haptics.heavy()
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SleepColor.muted)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(SleepSpacing.lg)
        // The glass draws its own edge; no manual border on top of it.
        .liquidGlass(cornerRadius: SleepRadius.lg, tint: SleepColor.glassWarm)
    }
}
