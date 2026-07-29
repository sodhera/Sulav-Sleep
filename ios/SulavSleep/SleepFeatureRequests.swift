import SwiftUI
#if canImport(Supabase)
import Supabase
#endif

// The feature request board: a public, signed-in-only list of ideas people
// have asked for, ordered by vote score, with a composer at the bottom.
// Reached from Settings → Feedback → "Request a feature".
//
// Everything for the feature lives in this one file — row models, the network
// boarding protocol, the screen's observable state, and the views — the same
// way `SleepScreenTime.swift` keeps FamilyControls in one place. The board is
// the only part of the app that talks to other users' data, so keeping its
// surface area in a single readable file is deliberate.
//
// **This is not `CloudSyncing`.** That protocol is best-effort background
// sync of the user's own record: every call swallows its error because the
// local device is the source of truth and a failed sync must never interrupt
// anyone. The board is the opposite on both counts — the server is the only
// source of truth, and a submit that silently fails is a user who thinks they
// were heard and wasn't. So these calls `throw` and the UI reports them.
//
// See `supabase/migrations/002_feature_requests.sql` for the table rules;
// the important one is that `score` is server-owned and votes are private.

// MARK: - Availability

enum FeatureRequestFlags {
    /// Whether the **public board** — other people's requests, the vote
    /// controls, "Most wanted" — is shown. The composer is unaffected: with
    /// this off, the screen is a private suggestion box that posts to the
    /// same table, and nobody sees anybody else's words.
    ///
    /// **Off deliberately.** App Store Guideline 1.2 requires an app that
    /// *displays* user-generated content to ship a way to filter objectionable
    /// material, a mechanism to report it, a way to block abusive users, and
    /// published contact info. The board has none of those yet, and it now
    /// attaches real names to posts, so shipping it as-is is a rejection risk.
    /// A submit-only form displays nothing to anyone and raises none of that.
    ///
    /// **To turn it back on**, build the moderation UI first — at minimum a
    /// per-request "Report" action and a way to block an author. The database
    /// side is already there: `status = 'hidden'` drops a row from every
    /// client read (migration 002), so taking content down is one UPDATE.
    /// Everything else the board needs — fetch, ranking, voting, paging,
    /// expansion — is written and working; only this flag and the moderation
    /// affordances stand between here and shipping it.
    static let showsPublicBoard = false
}

// MARK: - Limits

enum FeatureRequestLimits {
    /// Mirrors the `feature_requests_title_length` check in migration 002 —
    /// if you change either, change both, or the server starts rejecting text
    /// the client happily accepted.
    static let maxTitle = 140
    static let minTitle = 3

    /// How many requests are visible before "Show more". A board is a thing
    /// you skim, not a feed you fall into: five is enough to see what the
    /// popular asks are without the screen turning into an endless scroll.
    static let pageSize = 5

    /// Lines a collapsed card shows. Space for both is always reserved (see
    /// `FeatureRequestCard`), so every collapsed card is the same height
    /// whether its request is three words or three lines.
    static let collapsedLines = 2
}

// MARK: - Model

enum FeatureRequestStatus: String, Codable, Sendable {
    case open
    case planned
    case shipped

    /// Only statuses worth a badge return one; `open` is the unmarked default
    /// so a board of ordinary requests carries no chrome at all.
    var badge: String? {
        switch self {
        case .open: return nil
        case .planned: return "Planned"
        case .shipped: return "Shipped"
        }
    }

    var badgeColor: Color {
        self == .shipped ? SleepColor.gold : SleepColor.amber
    }
}

/// One idea on the board. `myVote` is merged in client-side from the user's
/// own ballots — the server never tells anyone how another person voted.
struct FeatureRequest: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    /// Snapshotted onto the row server-side when it was posted (migration
    /// 003), never sent by the client and never joined from `profiles` —
    /// which stays private. A user who later renames themselves keeps the old
    /// name on old posts, which is correct for a board but does mean this can
    /// differ from the name in Settings.
    let authorName: String
    var score: Int
    var status: FeatureRequestStatus
    let createdAt: Date
    /// -1, 0, or +1.
    var myVote: Int
}

// MARK: - Boarding protocol (testable)

/// Network surface for the board. Mirrors `CloudSyncing`'s protocol + factory
/// + disabled-stub shape so the app keeps one way of doing remote work, but
/// these calls throw rather than swallowing failure (see the file header).
protocol FeatureRequestBoarding: Sendable {
    func fetchRequests(userId: String) async throws -> [FeatureRequest]
    func submit(title: String, userId: String) async throws -> FeatureRequest
    /// `value` is -1, 0 (retract), or +1.
    func setVote(_ value: Int, requestId: String, userId: String) async throws
}

enum FeatureRequestBoard {
    /// Real Supabase board when a shared client exists, otherwise a stub that
    /// reads empty and refuses writes with a plain-English reason.
    static func makeDefault() -> FeatureRequestBoarding {
        #if canImport(Supabase)
        guard let client = SulavAuth.sharedClient else { return DisabledFeatureRequestBoard() }
        return SupabaseFeatureRequestBoard(client: client)
        #else
        return DisabledFeatureRequestBoard()
        #endif
    }
}

/// Surfaced verbatim to the user, so every case reads as a sentence rather
/// than an error code.
enum FeatureRequestError: LocalizedError {
    case notSignedIn
    case unavailable
    case tooShort
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "Sign in to post a request."
        case .unavailable: return "The request board isn't available in this build."
        case .tooShort: return "Say a little more about what you'd like."
        case .server(let message): return message
        }
    }
}

// MARK: - Disabled stub

struct DisabledFeatureRequestBoard: FeatureRequestBoarding {
    func fetchRequests(userId: String) async throws -> [FeatureRequest] { [] }
    func submit(title: String, userId: String) async throws -> FeatureRequest {
        throw FeatureRequestError.unavailable
    }
    func setVote(_ value: Int, requestId: String, userId: String) async throws {
        throw FeatureRequestError.unavailable
    }
}

#if canImport(Supabase)

// MARK: - Row models

private struct FeatureRequestRow: Decodable {
    let id: String
    let title: String
    let author_name: String?
    let status: String
    let score: Int
    let created_at: String

    /// The column list every board query selects. One constant so a new
    /// column can't be added to the decode struct and forgotten in a query.
    static let columns = "id,title,author_name,status,score,created_at"

    func asRequest(myVote: Int) -> FeatureRequest {
        FeatureRequest(
            id: id,
            title: title,
            // Optional only to cover a NULL/empty column, not a missing one:
            // the select names `author_name` explicitly, so a client running
            // ahead of migration 003 fails the whole query rather than
            // degrading. That's deliberate — the alternative, `select *`,
            // would ship every other user's `author_id` to every client.
            authorName: (author_name?.isEmpty == false) ? author_name! : "Someone",
            score: score,
            status: FeatureRequestStatus(rawValue: status) ?? .open,
            createdAt: PostgresDate.parse(created_at),
            myVote: myVote
        )
    }
}

private struct NewFeatureRequestRow: Encodable {
    /// Client-generated so a submit can be retried safely — see
    /// `SupabaseFeatureRequestBoard.submit`. The column has a
    /// `gen_random_uuid()` default, so supplying it is optional server-side.
    let id: String
    let author_id: String
    let title: String
}

private struct VoteRow: Codable {
    let request_id: String
    let user_id: String
    let value: Int
}

private struct MyVoteRow: Decodable {
    let request_id: String
    let value: Int
}

/// PostgREST hands back `timestamptz` with a microsecond fraction
/// ("...T15:04:05.123456+00:00"), which `ISO8601DateFormatter` refuses even
/// with `.withFractionalSeconds` (it wants at most milliseconds). Trimming
/// the fraction to three digits before parsing is what makes these dates
/// decode at all; the board only ever renders them as a coarse relative age
/// ("3d"), so the discarded precision costs nothing.
private enum PostgresDate {
    static func parse(_ raw: String) -> Date {
        if let date = withFraction.date(from: normalized(raw)) { return date }
        if let date = plain.date(from: raw) { return date }
        return Date()
    }

    /// Clamp any fractional-second run to three digits.
    private static func normalized(_ raw: String) -> String {
        guard let dot = raw.firstIndex(of: ".") else { return raw }
        let afterDot = raw.index(after: dot)
        guard let endOfDigits = raw[afterDot...].firstIndex(where: { !$0.isNumber }) else { return raw }
        let digits = raw[afterDot ..< endOfDigits]
        guard digits.count > 3 else { return raw }

        // Built stepwise with explicit `String`s: the one-line
        // `String(...) + Substring + String(...)` form this replaced sent the
        // type checker over its time budget.
        var result = String(raw[..<afterDot])
        result += String(digits.prefix(3))
        result += String(raw[endOfDigits...])
        return result
    }

    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}

// MARK: - Supabase implementation

final class SupabaseFeatureRequestBoard: FeatureRequestBoarding, @unchecked Sendable {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    // MARK: - Transient failure handling

    /// Runs `work`, and retries it **once** if it failed with a dropped
    /// connection rather than a real server refusal.
    ///
    /// Observed in practice: tapping a vote arrow would intermittently fail
    /// with `NSURLErrorNetworkConnectionLost` while the identical tap
    /// succeeded a second later. That's URLSession reusing a keep-alive
    /// connection the server had already closed — nothing to do with
    /// permissions, and nothing the user can act on, so surfacing it as
    /// "Couldn't save your vote" was both alarming and useless.
    ///
    /// Only safe for **idempotent** calls, which is why `submit` deliberately
    /// does not use it: the vote upsert and delete are keyed by
    /// `(request_id, user_id)` and the board read is a plain select, so
    /// running either twice is indistinguishable from running it once. An
    /// insert is not — if the connection dropped *after* the server committed
    /// it, a retry would post the same idea twice.
    /// `@discardableResult` because the vote calls care only that the write
    /// landed, not what PostgREST echoed back.
    @discardableResult
    private func retryingDroppedConnection<T>(
        _ work: () async throws -> T
    ) async throws -> T {
        do {
            return try await work()
        } catch {
            guard Self.isDroppedConnection(error) else { throw error }
            AppLog.app.info("Board: connection dropped, retrying once")
            // A beat for URLSession to discard the dead connection rather than
            // immediately handing back the same one.
            try? await Task.sleep(for: .milliseconds(250))
            return try await work()
        }
    }

    private static func isDroppedConnection(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return false }
        return [
            NSURLErrorNetworkConnectionLost,
            NSURLErrorTimedOut,
            NSURLErrorCannotConnectToHost,
            NSURLErrorCannotFindHost,
            NSURLErrorDNSLookupFailed,
        ].contains(nsError.code)
    }

    /// Two reads, merged locally: the public board, and this user's own
    /// ballots. They can't be one join — RLS only ever returns the caller's
    /// own vote rows, which is exactly the privacy property we want, so the
    /// "did I vote on this" flag has to be stitched on client-side.
    func fetchRequests(userId: String) async throws -> [FeatureRequest] {
        do {
            let rows: [FeatureRequestRow] = try await retryingDroppedConnection {
                try await client
                    .from("feature_requests")
                    .select(FeatureRequestRow.columns)
                    .order("score", ascending: false)
                    .order("created_at", ascending: false)
                    .limit(50)
                    .execute()
                    .value
            }

            let votes: [MyVoteRow] = try await retryingDroppedConnection {
                try await client
                    .from("feature_request_votes")
                    .select("request_id,value")
                    .eq("user_id", value: userId)
                    .execute()
                    .value
            }

            let byRequest = Dictionary(votes.map { ($0.request_id, $0.value) }, uniquingKeysWith: { a, _ in a })
            return rows.map { $0.asRequest(myVote: byRequest[$0.id] ?? 0) }
        } catch {
            AppLog.app.error("Board: fetch failed: \(error.localizedDescription, privacy: .public)")
            throw FeatureRequestError.server("Couldn't load the board. Check your connection and try again.")
        }
    }

    /// Posts a request, retrying once on a dropped connection.
    ///
    /// A plain insert is not idempotent, which is why this originally didn't
    /// retry at all: if the connection dies *after* the server committed the
    /// row, retrying posts the same idea twice. The **client-generated id**
    /// fixes that — it's an idempotency key. On the retry, one of two things
    /// is true: the first attempt never landed (the insert succeeds), or it
    /// did (the insert fails on the primary key, which tells us it worked, so
    /// we read the row back and report success). Either way the user gets one
    /// request and one honest answer.
    ///
    /// Worth the extra code because this screen's *only* job is posting, and
    /// `NSURLErrorNetworkConnectionLost` on a first tap is common enough to
    /// see routinely (the same fault the vote path retries around).
    func submit(title: String, userId: String) async throws -> FeatureRequest {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= FeatureRequestLimits.minTitle else { throw FeatureRequestError.tooShort }
        let requestID = UUID().uuidString.lowercased()

        do {
            do {
                return try await insert(id: requestID, title: trimmed, userId: userId)
            } catch let first where Self.isDroppedConnection(first) {
                AppLog.app.info("Board: submit connection dropped, retrying once")
                try? await Task.sleep(for: .milliseconds(250))
                do {
                    return try await insert(id: requestID, title: trimmed, userId: userId)
                } catch let second where Self.isDuplicateKey(second) {
                    // The first attempt did land; the connection died on the
                    // way back. Read our own row and treat it as the success
                    // it was.
                    AppLog.app.info("Board: retry hit the first insert — treating as success")
                    if let existing = try? await fetchRequest(id: requestID) { return existing }
                    throw second
                }
            }
        } catch {
            AppLog.app.error("Board: submit failed: \(error.localizedDescription, privacy: .public)")
            // The daily quota trigger raises a human-readable message; pass it
            // through so a rate-limited user learns why instead of seeing a
            // generic failure they'd only retry.
            let raw = error.localizedDescription
            if raw.contains("limit reached") {
                throw FeatureRequestError.server("That's five requests today — try again tomorrow.")
            }
            throw FeatureRequestError.server("Couldn't post that. Try again in a moment.")
        }
    }

    /// One insert attempt, returning the created row.
    private func insert(id: String, title: String, userId: String) async throws -> FeatureRequest {
        let row: FeatureRequestRow = try await client
            .from("feature_requests")
            .insert(NewFeatureRequestRow(id: id, author_id: userId, title: title))
            .select(FeatureRequestRow.columns)
            .single()
            .execute()
            .value
        AppLog.app.info("Board: request submitted")
        return row.asRequest(myVote: 0)
    }

    /// Reads back a single request by id — only used to confirm a retry that
    /// collided with its own first attempt.
    private func fetchRequest(id: String) async throws -> FeatureRequest? {
        let rows: [FeatureRequestRow] = try await client
            .from("feature_requests")
            .select(FeatureRequestRow.columns)
            .eq("id", value: id)
            .limit(1)
            .execute()
            .value
        return rows.first.map { $0.asRequest(myVote: 0) }
    }

    /// A primary-key collision, i.e. "this exact row already exists".
    private static func isDuplicateKey(_ error: Error) -> Bool {
        let text = error.localizedDescription.lowercased()
        return text.contains("duplicate key") || text.contains("23505")
    }

    func setVote(_ value: Int, requestId: String, userId: String) async throws {
        do {
            try await retryingDroppedConnection {
                if value == 0 {
                    try await client
                        .from("feature_request_votes")
                        .delete()
                        .eq("request_id", value: requestId)
                        .eq("user_id", value: userId)
                        .execute()
                } else {
                    try await client
                        .from("feature_request_votes")
                        .upsert(
                            VoteRow(request_id: requestId, user_id: userId, value: value),
                            onConflict: "request_id,user_id"
                        )
                        .execute()
                }
            }
        } catch {
            AppLog.app.error("Board: vote failed: \(error.localizedDescription, privacy: .public)")
            throw FeatureRequestError.server("Couldn't save your vote.")
        }
    }
}

#endif

// MARK: - Screen state

/// Observable state for the board screen. Votes apply **optimistically** —
/// the row moves the instant it's tapped and rolls back if the write fails —
/// because a vote is a one-tap gesture and a spinner on it would feel broken.
/// Submits do the opposite and wait for the server, since the user needs to
/// know their words actually landed.
@Observable
@MainActor
final class FeatureRequestBoardModel {
    private(set) var requests: [FeatureRequest] = []
    private(set) var isLoading = false
    private(set) var isSubmitting = false
    var draft = ""
    var errorMessage: String?
    /// Set after a successful post. With the public board hidden, the list a
    /// new request used to appear in isn't there, so this drives an explicit
    /// confirmation — otherwise a submit is a button that empties a field and
    /// says nothing, which reads as a failure.
    private(set) var didSubmit = false

    private let board: FeatureRequestBoarding
    private let userId: String?

    init(board: FeatureRequestBoarding = FeatureRequestBoard.makeDefault(), userId: String?) {
        self.board = board
        self.userId = userId
    }

    /// No upper bound needed: the composer clamps typing at `maxTitle`, so the
    /// draft can't exceed it.
    var canSubmit: Bool {
        !isSubmitting
            && draft.trimmingCharacters(in: .whitespacesAndNewlines).count >= FeatureRequestLimits.minTitle
    }

    func load() async {
        guard let userId else {
            errorMessage = FeatureRequestError.notSignedIn.errorDescription
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            requests = try await board.fetchRequests(userId: userId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func submit() async {
        guard let userId else {
            errorMessage = FeatureRequestError.notSignedIn.errorDescription
            return
        }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= FeatureRequestLimits.minTitle else { return }

        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let created = try await board.submit(title: text, userId: userId)
            draft = ""
            // Your own idea lands at the top regardless of score, so the
            // submit visibly did something even on a busy board.
            requests.insert(created, at: 0)
            didSubmit = true
            Haptics.success()
        } catch {
            errorMessage = error.localizedDescription
            Haptics.heavy()
        }
    }

    /// Back to the composer after a confirmation, for someone with a second
    /// idea.
    func resetAfterSubmit() { didSubmit = false }

    /// Tapping the arrow you already chose retracts the vote (sets it to 0) —
    /// the standard toggle, so there's always a way back from a mis-tap.
    func vote(_ direction: Int, on request: FeatureRequest) async {
        guard let userId else {
            errorMessage = FeatureRequestError.notSignedIn.errorDescription
            return
        }
        guard let index = requests.firstIndex(where: { $0.id == request.id }) else { return }

        let previous = requests[index]
        let newVote = previous.myVote == direction ? 0 : direction

        requests[index].myVote = newVote
        requests[index].score += newVote - previous.myVote
        Haptics.heavy()

        do {
            try await board.setVote(newVote, requestId: request.id, userId: userId)
        } catch {
            if let rollback = requests.firstIndex(where: { $0.id == request.id }) {
                requests[rollback] = previous
            }
            errorMessage = error.localizedDescription
        }
    }

}

// MARK: - Screen

/// Pushed from Settings. Same scaffold as every other sub-page: the scene
/// background, a glass back chevron, a left-aligned editorial title.
struct FeatureRequestsScreen: View {
    var store: SleepStore

    @State private var model: FeatureRequestBoardModel?
    @State private var visibleCount = FeatureRequestLimits.pageSize
    @FocusState private var composerFocused: Bool

    var body: some View {
        SceneScreen {
            SubpageHeader(
                title: "Request a feature",
                subtitle: FeatureRequestFlags.showsPublicBoard
                    ? "Ask for what you want, and vote on what everyone else asked for."
                    : "Tell us what SleepBlock should do next."
            )

            if let model {
                if model.didSubmit {
                    thanks(model)
                        .padding(.top, SleepSpacing.huge)
                } else {
                    composer(model)
                        .padding(.top, SleepSpacing.huge)
                }

                if FeatureRequestFlags.showsPublicBoard {
                    board(model)
                        .padding(.top, SleepSpacing.huge)
                }
            }
        }
        .task {
            if model == nil {
                model = FeatureRequestBoardModel(userId: store.account?.id)
            }
            // No board, no reason to fetch — and no reason to risk a
            // "couldn't load the board" alert on a screen with no board.
            if FeatureRequestFlags.showsPublicBoard {
                await model?.load()
            }
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { model?.errorMessage != nil },
                set: { if !$0 { model?.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { Haptics.heavy() }
        } message: {
            Text(model?.errorMessage ?? "Please try again.")
        }
    }

    // MARK: Composer

    /// A plain glass field over the primary button — the same "one clear
    /// action" shape as the schedule screen's Save, so posting reads as a
    /// deliberate act rather than an inline text box you might trip over.
    @ViewBuilder
    private func composer(_ model: FeatureRequestBoardModel) -> some View {
        VStack(alignment: .leading, spacing: SleepSpacing.md) {
            Text("Your idea").sectionLabel()

            TextField(
                "",
                // The cap is enforced on the way *in* rather than by
                // disabling the button at 141: a field that quietly stops
                // accepting characters teaches the limit immediately, where a
                // dead button leaves you deleting text to work out why. It
                // also means the draft can never violate migration 002's
                // length check, so the server can't reject what we accepted.
                text: Binding(
                    get: { model.draft },
                    set: { model.draft = String($0.prefix(FeatureRequestLimits.maxTitle)) }
                ),
                prompt: Text("A shortcut for naps…").foregroundStyle(SleepColor.muted),
                axis: .vertical
            )
            .font(SleepFont.body(16))
            .foregroundStyle(SleepColor.ink)
            .tint(SleepColor.amber)
            .lineLimit(1 ... 4)
            .focused($composerFocused)
            .submitLabel(.done)
            .padding(SleepSpacing.lg)
            .liquidGlass(cornerRadius: SleepRadius.lg)

            // Amber only once you've actually hit the ceiling — the count is
            // a quiet fact until it becomes a constraint.
            Text("\(model.draft.count)/\(FeatureRequestLimits.maxTitle)")
                .font(SleepFont.body(12))
                .foregroundStyle(
                    model.draft.count >= FeatureRequestLimits.maxTitle
                        ? SleepColor.amber : SleepColor.faint
                )
                .monospacedDigit()

            // No glyph: "Post request" already says what the button does, and
            // the paper plane was decoration on the one control that needed
            // none.
            LiquidPrimaryButton(title: "Post request", isLoading: model.isSubmitting) {
                composerFocused = false
                Task { await model.submit() }
            }
            .disabled(!model.canSubmit)
            .opacity(model.canSubmit ? 1 : 0.5)
        }
    }

    // MARK: Confirmation

    /// What a submit looks like when there's no list for the new request to
    /// land in — the app's warm glyph-row pattern, plus a way back for a
    /// second idea. The sent request is deliberately *not* echoed back: it's
    /// still on screen nowhere else, and quoting it invites editing that the
    /// board doesn't support.
    private func thanks(_ model: FeatureRequestBoardModel) -> some View {
        VStack(alignment: .leading, spacing: SleepSpacing.lg) {
            HStack(alignment: .top, spacing: SleepSpacing.md) {
                Image(systemName: "checkmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(SleepColor.amber)
                    .frame(width: 40, height: 40)
                    .background { Circle().fill(SleepColor.glassWarm) }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Request sent")
                        .font(SleepFont.title(16))
                        .foregroundStyle(SleepColor.ink)
                    Text("Thanks — every one gets read.")
                        .font(SleepFont.body(13))
                        .foregroundStyle(SleepColor.dim)
                }
                .padding(.top, 2)

                Spacer(minLength: 0)
            }

            Button {
                Haptics.heavy()
                model.resetAfterSubmit()
            } label: {
                Text("Send another")
                    .font(SleepFont.label(14))
                    .foregroundStyle(SleepColor.dim)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Board

    @ViewBuilder
    private func board(_ model: FeatureRequestBoardModel) -> some View {
        VStack(alignment: .leading, spacing: SleepSpacing.md) {
            HStack {
                Text("Most wanted").sectionLabel()
                Spacer()
                if model.isLoading {
                    ProgressView().controlSize(.small).tint(SleepColor.amber)
                }
            }

            if model.requests.isEmpty && !model.isLoading {
                // The app's standard empty state: a warm glyph beside one
                // short line, never a ghost list of fake requests.
                HStack(alignment: .top, spacing: SleepSpacing.md) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(SleepColor.amber)
                        .frame(width: 40, height: 40)
                        .background { Circle().fill(SleepColor.glassWarm) }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Nothing here yet")
                            .font(SleepFont.title(16))
                            .foregroundStyle(SleepColor.ink)
                        Text("Be the first to ask for something.")
                            .font(SleepFont.body(13))
                            .foregroundStyle(SleepColor.dim)
                    }
                    .padding(.top, 2)
                }
                .padding(.top, SleepSpacing.xs)
            } else {
                VStack(spacing: SleepSpacing.md) {
                    // Already ranked by the server (score desc, newest as the
                    // tiebreak), so "most wanted" is literal — this just takes
                    // the top slice.
                    ForEach(model.requests.prefix(visibleCount)) { request in
                        FeatureRequestCard(request: request) { direction in
                            Task { await model.vote(direction, on: request) }
                        }
                    }

                    if model.requests.count > visibleCount {
                        showMoreButton(remaining: model.requests.count - visibleCount)
                    }
                }
            }
        }
    }

    /// Reveals the next page. A button rather than infinite scroll on purpose:
    /// the board is something you skim and leave, and a list that keeps
    /// growing under your thumb is the opposite of what this app is for.
    private func showMoreButton(remaining: Int) -> some View {
        Button {
            Haptics.heavy()
            withAnimation(.easeInOut(duration: 0.25)) {
                visibleCount += FeatureRequestLimits.pageSize
            }
        } label: {
            HStack(spacing: SleepSpacing.xs) {
                Text("Show \(min(FeatureRequestLimits.pageSize, remaining)) more")
                    .font(SleepFont.label(14))
                    .foregroundStyle(SleepColor.dim)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(SleepColor.faint)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, SleepSpacing.xs)
    }
}

// MARK: - Row

/// One request: the vote control on the left where the eye lands first (the
/// score is the point of the board), the text to its right.
///
/// The control is a vertical chevron / score / chevron stack rather than two
/// buttons in a row, because the score has to sit *between* the arrows for
/// "up raises this number" to be legible without a label. Only the chosen
/// arrow takes color — an unvoted row is entirely quiet, so a long board
/// doesn't read as a field of amber.
private struct FeatureRequestCard: View {
    let request: FeatureRequest
    let onVote: (Int) -> Void

    @State private var isExpanded = false
    /// Whether the collapsed title is actually being clipped. Measured rather
    /// than guessed from character count, which would mis-fire on narrow
    /// glyphs, wide ones, and every Dynamic Type size.
    @State private var canExpand = false
    @State private var clampedHeight: CGFloat = 0
    @State private var naturalHeight: CGFloat = 0

    private static let titleFont = SleepFont.body(15)

    var body: some View {
        HStack(alignment: .top, spacing: SleepSpacing.lg) {
            voteControl

            VStack(alignment: .leading, spacing: SleepSpacing.sm) {
                title

                if canExpand {
                    Button {
                        Haptics.heavy()
                        withAnimation(.easeInOut(duration: 0.22)) { isExpanded.toggle() }
                    } label: {
                        Text(isExpanded ? "See less" : "See more")
                            .font(SleepFont.label(12))
                            .foregroundStyle(SleepColor.amber)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                // Who asked, then when. The name is the brighter of the two
                // because it's the fact worth reading; the age is a faint
                // afterthought, since the board ranks by votes not recency.
                HStack(spacing: SleepSpacing.sm) {
                    if let badge = request.status.badge {
                        Text(badge)
                            .font(SleepFont.label(11))
                            .foregroundStyle(request.status.badgeColor)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background {
                                Capsule().fill(request.status.badgeColor.opacity(0.14))
                            }
                    }
                    Text(request.authorName)
                        .font(SleepFont.body(12))
                        .foregroundStyle(SleepColor.dim)
                        .lineLimit(1)
                    Text("·")
                        .font(SleepFont.body(12))
                        .foregroundStyle(SleepColor.faint)
                    Text(RelativeAge.string(from: request.createdAt))
                        .font(SleepFont.body(12))
                        .foregroundStyle(SleepColor.faint)
                }
            }
        }
        .padding(SleepSpacing.lg)
        .liquidGlass(cornerRadius: SleepRadius.lg)
    }

    /// The request text. Collapsed, it shows `collapsedLines` and **reserves
    /// space for all of them** — that's what gives every card the same
    /// standing height, so a board of one-liners and paragraphs still reads
    /// as an even stack rather than a ragged one.
    ///
    /// Truncation is detected by rendering an invisible, unclamped copy
    /// behind the visible text and comparing heights. It's the only reliable
    /// way to ask SwiftUI "did you actually clip this?", and it's why a short
    /// request never grows a pointless "See more".
    private var title: some View {
        Group {
            if isExpanded {
                Text(request.title)
                    .font(Self.titleFont)
            } else {
                Text(request.title)
                    .font(Self.titleFont)
                    .lineLimit(FeatureRequestLimits.collapsedLines, reservesSpace: true)
            }
        }
        .foregroundStyle(SleepColor.ink)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: ClampedTitleHeight.self, value: proxy.size.height)
            }
        }
        .background(alignment: .topLeading) {
            Text(request.title)
                .font(Self.titleFont)
                .fixedSize(horizontal: false, vertical: true)
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(key: NaturalTitleHeight.self, value: proxy.size.height)
                    }
                }
                .hidden()
                .accessibilityHidden(true)
        }
        .onPreferenceChange(ClampedTitleHeight.self) { height in
            clampedHeight = height
            refreshExpandability()
        }
        .onPreferenceChange(NaturalTitleHeight.self) { height in
            naturalHeight = height
            refreshExpandability()
        }
    }

    /// Only meaningful while collapsed — expanded, the two heights match by
    /// definition, and recomputing then would delete the "See less" button
    /// the user just used.
    private func refreshExpandability() {
        guard !isExpanded, clampedHeight > 0, naturalHeight > 0 else { return }
        canExpand = naturalHeight > clampedHeight + 1
    }

    private var voteControl: some View {
        VStack(spacing: 2) {
            arrow("chevron.up", direction: 1)

            Text("\(request.score)")
                .font(SleepFont.title(15))
                .foregroundStyle(SleepColor.ink)
                .monospacedDigit()
                .frame(minWidth: 24)

            arrow("chevron.down", direction: -1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(request.score) votes. \(request.title). Asked by \(request.authorName)")
        .accessibilityValue(
            request.myVote == 1 ? "Upvoted" : request.myVote == -1 ? "Downvoted" : "Not voted"
        )
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onVote(1)
            case .decrement: onVote(-1)
            default: break
            }
        }
    }

    private func arrow(_ symbol: String, direction: Int) -> some View {
        Button {
            onVote(direction)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(request.myVote == direction ? SleepColor.amber : SleepColor.faint)
                .frame(width: 32, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHidden(true)
    }
}

/// Height of the title as drawn (clamped when collapsed) and as it would be
/// with no line limit. Two separate keys because one shared key would reduce
/// the pair to a single max and the comparison would always be equal.
private struct ClampedTitleHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct NaturalTitleHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Coarse ages only ("now", "4h", "3d", "2w"). The board is ranked by votes,
/// not recency, so an exact timestamp would be precision nobody acts on.
private enum RelativeAge {
    static func string(from date: Date) -> String {
        let seconds = max(0, Date().timeIntervalSince(date))
        switch seconds {
        case ..<3600: return "now"
        case ..<86_400: return "\(Int(seconds / 3600))h"
        case ..<604_800: return "\(Int(seconds / 86_400))d"
        default: return "\(Int(seconds / 604_800))w"
        }
    }
}
