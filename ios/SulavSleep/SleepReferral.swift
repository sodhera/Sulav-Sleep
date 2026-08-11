import Foundation
import Supabase

// The referral + sleep partner program, behind the app's usual protocol
// seam (`CloudSyncing`, `AuthProviding`…) so the store and views never
// import the SDK. See docs/roadmap-partner-referral.md for the full spec;
// the short version:
//
//   * One code per account. A friend redeeming it gets 30 free nights
//     (server-dated `free_until` — the lock exemption in `SleepStore`),
//     and their redemption files a *pending* partnership request.
//   * Nothing is shared until the inviter confirms; then each side reads
//     the other's `partner_summaries` row — derived numbers only (streak,
//     average bed/wake/duration), never raw sessions. That table's RLS
//     policy is the whole privacy model.
//   * When a referred friend makes their first *paid* payment, the
//     referrer banks a free month — entirely server-side (RevenueCat
//     webhook → App Store renewal extension); the app only displays it.
//
// Redemption goes through the `redeem-referral` Edge Function (the checks
// live server-side); partnership state changes go through SECURITY DEFINER
// RPCs; reads are plain PostgREST under RLS.

// MARK: - Models

/// The caller's own standing as a *redeemer* of someone else's code.
struct ReferralStanding: Equatable {
    /// End of the granted free nights. The lock compares against this.
    var freeUntil: Date
    /// Whether the first paid payment has happened (display only).
    var converted: Bool
}

/// One confirmed sleep partner. `name` comes off the partnership row (copied
/// when the invite was accepted), so the list always has something to show
/// even before the partner's own `summary` has synced. Partnerships are
/// auto-confirmed on invite-link accept — there is no pending/request state.
struct PartnerLink: Identifiable, Equatable {
    var partnershipID: String
    var partnerUserID: String
    var name: String
    /// The partner's shared numbers; nil until their device has pushed one.
    var summary: PartnerSummary?

    var id: String { partnershipID }
    /// The summary's name wins once it exists (it's self-set and current);
    /// the partnership-row name is the fallback for a partner who's never
    /// synced.
    var displayName: String {
        if let n = summary?.name, !n.isEmpty { return n }
        return name.isEmpty ? "Your partner" : name
    }
}

/// The derived numbers a confirmed partner may see — the partner-facing
/// mirror of `SleepStreak` + `SleepAverages`.
struct PartnerSummary: Equatable {
    var name: String
    var streak: Int
    var streakDying: Bool
    var avgBedMinutes: Int?
    var avgWakeMinutes: Int?
    var avgDurationMinutes: Int?
    var nights: Int
    var updatedAt: Date?
}

/// The caller's standing as a *referrer*: how the invite is doing.
struct ReferrerStats: Equatable {
    var invitedCount: Int
    var convertedCount: Int
}

// MARK: - Protocol

protocol ReferralSyncing: Sendable {
    /// False in dev mode (no Supabase) — every referral/partner surface hides.
    var isConfigured: Bool { get }
    /// The caller's shareable code, created server-side on first ask.
    func myCode() async -> String?
    /// Redeem a friend's code. Returns the granted `free_until`, or throws
    /// with a user-facing message (the Edge Function's own).
    func redeem(code: String) async throws -> Date
    /// The caller's own redemption, if they ever made one.
    func myStanding() async -> ReferralStanding?
    /// How the caller's invites are doing (Settings row).
    func referrerStats() async -> ReferrerStats?
    /// The caller's confirmed partners, each with their summary. One round
    /// trip for the partnerships, one for the summaries.
    func partners(myUserID: String) async -> [PartnerLink]?
    /// Mint a one-time partner invite token (behind the shareable link).
    func createPartnerInvite() async throws -> String
    /// Accept a partner invite by its token — connects both accounts. Returns
    /// the new partner's display name. Throws the server's user-facing message.
    func acceptPartnerInvite(token: String) async throws -> String
    /// Leave a partnership (either side, immediate).
    func unlinkPartnership(id: String) async throws
    /// Owner-side write of the shared summary row. Best-effort like every
    /// cloud call: failures log, the next sync retries.
    func upsertMySummary(_ summary: PartnerSummary, userId: String) async
}

/// User-facing referral failures, mirroring `SubscriptionError`.
struct ReferralError: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}

// MARK: - Factory

enum SleepReferral {
    static func makeDefault() -> ReferralSyncing {
        guard let client = SulavAuth.sharedClient else {
            return DisabledReferralService()
        }
        return SupabaseReferralService(client: client)
    }
}

// MARK: - Disabled (dev mode)

struct DisabledReferralService: ReferralSyncing {
    var isConfigured: Bool { false }
    func myCode() async -> String? { nil }
    func redeem(code: String) async throws -> Date {
        throw ReferralError(message: "Referrals aren't available in this build.")
    }
    func myStanding() async -> ReferralStanding? { nil }
    func referrerStats() async -> ReferrerStats? { nil }
    func partners(myUserID: String) async -> [PartnerLink]? { nil }
    func createPartnerInvite() async throws -> String {
        throw ReferralError(message: "Partners aren't available in this build.")
    }
    func acceptPartnerInvite(token: String) async throws -> String {
        throw ReferralError(message: "Partners aren't available in this build.")
    }
    func unlinkPartnership(id: String) async throws {}
    func upsertMySummary(_ summary: PartnerSummary, userId: String) async {}
}

// MARK: - Row models (PostgREST, snake_case)

private struct RedemptionRow: Decodable {
    let free_until: String
    let converted_at: String?
}

private struct ReferrerRedemptionRow: Decodable {
    let converted_at: String?
}

private struct PartnershipRow: Decodable {
    let id: UUID
    let inviter_id: UUID
    let invitee_id: UUID
    let inviter_name: String
    let invitee_name: String
    let status: String
}

private struct SummaryRow: Codable {
    let user_id: String
    let name: String
    let streak: Int
    let streak_dying: Bool
    let avg_bed_minutes: Int?
    let avg_wake_minutes: Int?
    let avg_duration_minutes: Int?
    let nights: Int
    var updated_at: String?

    var asSummary: PartnerSummary {
        PartnerSummary(
            name: name,
            streak: streak,
            streakDying: streak_dying,
            avgBedMinutes: avg_bed_minutes,
            avgWakeMinutes: avg_wake_minutes,
            avgDurationMinutes: avg_duration_minutes,
            nights: nights,
            updatedAt: updated_at.flatMap(SleepReferralDates.date(from:))
        )
    }
}

private struct RedeemResponse: Decodable {
    let free_until: String
}

private struct RedeemErrorResponse: Decodable {
    let error: String
}

/// Same two-formatter timestamptz dance as `SessionRow` — Postgres trims
/// fractional seconds, and one ISO8601 formatter can't parse both shapes.
enum SleepReferralDates {
    static func date(from raw: String) -> Date? {
        isoFractional.date(from: raw) ?? isoWhole.date(from: raw)
    }
    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoWhole: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}

// MARK: - Real Supabase implementation

final class SupabaseReferralService: ReferralSyncing, @unchecked Sendable {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    var isConfigured: Bool { true }

    func myCode() async -> String? {
        do {
            let code: String = try await client
                .rpc("get_or_create_referral_code")
                .execute()
                .value
            return code
        } catch {
            AppLog.app.error("Referral: code fetch failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func redeem(code: String) async throws -> Date {
        do {
            let response: RedeemResponse = try await client.functions.invoke(
                "redeem-referral",
                options: FunctionInvokeOptions(body: ["code": code])
            )
            guard let date = SleepReferralDates.date(from: response.free_until) else {
                throw ReferralError(message: "Unexpected server response. Try again.")
            }
            AppLog.app.info("Referral: code redeemed")
            return date
        } catch let error as FunctionsError {
            // The Edge Function speaks user-facing messages; surface them.
            if case let .httpError(_, data) = error,
               let body = try? JSONDecoder().decode(RedeemErrorResponse.self, from: data) {
                throw ReferralError(message: body.error)
            }
            throw ReferralError(message: "Couldn't reach the server. Check your connection and try again.")
        } catch let error as ReferralError {
            throw error
        } catch {
            throw ReferralError(message: "Couldn't redeem the code. Try again in a moment.")
        }
    }

    func myStanding() async -> ReferralStanding? {
        do {
            // RLS returns the caller's rows on *either* side; the standing is
            // specifically the one where they are the invitee (PK, so ≤1).
            guard let uid = try? await client.auth.session.user.id else { return nil }
            let rows: [RedemptionRow] = try await client
                .from("referral_redemptions")
                .select("free_until, converted_at")
                .eq("invitee_id", value: uid.uuidString.lowercased())
                .limit(1)
                .execute()
                .value
            guard let row = rows.first,
                  let until = SleepReferralDates.date(from: row.free_until) else { return nil }
            return ReferralStanding(freeUntil: until, converted: row.converted_at != nil)
        } catch {
            AppLog.app.error("Referral: standing fetch failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func referrerStats() async -> ReferrerStats? {
        do {
            // RLS returns rows where the caller is invitee *or* referrer;
            // fetching only referrer-side rows needs the explicit filter.
            guard let uid = try? await client.auth.session.user.id else { return nil }
            let rows: [ReferrerRedemptionRow] = try await client
                .from("referral_redemptions")
                .select("converted_at")
                .eq("referrer_id", value: uid.uuidString.lowercased())
                .execute()
                .value
            return ReferrerStats(
                invitedCount: rows.count,
                convertedCount: rows.filter { $0.converted_at != nil }.count
            )
        } catch {
            AppLog.app.error("Referral: stats fetch failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func partners(myUserID: String) async -> [PartnerLink]? {
        do {
            let rows: [PartnershipRow] = try await client
                .from("partnerships")
                .select()
                .eq("status", value: "confirmed")
                .execute()  // RLS already scopes to the caller's rows
                .value
            let myID = myUserID.lowercased()
            var links: [PartnerLink] = rows.compactMap { row in
                let inviter = row.inviter_id.uuidString.lowercased()
                let invitee = row.invitee_id.uuidString.lowercased()
                let iAmInviter = inviter == myID
                // The *other* side is the partner; show their name, not mine.
                let partnerID = iAmInviter ? invitee : inviter
                let partnerName = iAmInviter ? row.invitee_name : row.inviter_name
                return PartnerLink(
                    partnershipID: row.id.uuidString.lowercased(),
                    partnerUserID: partnerID,
                    name: partnerName,
                    summary: nil
                )
            }
            // Each partner's summary in one query (RLS lets a confirmed
            // partner read exactly these rows).
            let ids = links.map(\.partnerUserID)
            if !ids.isEmpty {
                let summaries: [SummaryRow] = try await client
                    .from("partner_summaries")
                    .select()
                    .in("user_id", values: ids)
                    .execute()
                    .value
                let byID = Dictionary(uniqueKeysWithValues: summaries.map { ($0.user_id.lowercased(), $0.asSummary) })
                for i in links.indices {
                    links[i].summary = byID[links[i].partnerUserID]
                }
            }
            // Newest streaks first is arbitrary but stable; sort by name so the
            // list doesn't reshuffle between fetches.
            return links.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        } catch {
            AppLog.app.error("Partners: fetch failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func createPartnerInvite() async throws -> String {
        do {
            let token: String = try await client
                .rpc("create_partner_invite")
                .execute()
                .value
            AppLog.app.info("Partners: invite minted")
            return token
        } catch {
            AppLog.app.error("Partners: invite mint failed: \(error.localizedDescription, privacy: .public)")
            throw ReferralError(message: "Couldn't create an invite. Check your connection and try again.")
        }
    }

    func acceptPartnerInvite(token: String) async throws -> String {
        do {
            let name: String = try await client
                .rpc("accept_partner_invite", params: ["p_token": token])
                .execute()
                .value
            AppLog.app.info("Partners: invite accepted")
            return name
        } catch {
            // The RPC raises user-facing messages (expired, self, cap); surface them.
            throw ReferralError(message: Self.postgrestMessage(error)
                ?? "Couldn't accept the invite. It may have expired.")
        }
    }

    func unlinkPartnership(id: String) async throws {
        do {
            try await client.rpc("unlink_partnership", params: ["p_id": id]).execute()
            AppLog.app.info("Partners: unlinked")
        } catch {
            throw ReferralError(message: "Couldn't unlink. Try again.")
        }
    }

    /// Pulls the human message out of a PostgREST `raise exception`, so the
    /// RPC's own copy ("This invite has expired…") reaches the user.
    private static func postgrestMessage(_ error: Error) -> String? {
        if let pg = error as? PostgrestError, !pg.message.isEmpty { return pg.message }
        return nil
    }

    func upsertMySummary(_ summary: PartnerSummary, userId: String) async {
        let row = SummaryRow(
            user_id: userId,
            name: summary.name,
            streak: summary.streak,
            streak_dying: summary.streakDying,
            avg_bed_minutes: summary.avgBedMinutes,
            avg_wake_minutes: summary.avgWakeMinutes,
            avg_duration_minutes: summary.avgDurationMinutes,
            nights: summary.nights,
            updated_at: nil  // the trigger stamps it
        )
        do {
            try await client
                .from("partner_summaries")
                .upsert(row, onConflict: "user_id")
                .execute()
            AppLog.app.info("Referral: summary pushed")
        } catch {
            AppLog.app.error("Referral: summary push failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
