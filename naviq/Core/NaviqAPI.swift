import Foundation

/// Typed endpoints. Views and models call these, never raw paths.
enum NaviqAPI {
    private static var client: APIClient { .shared }

    // MARK: Auth
    static func register(name: String, email: String, password: String) async throws -> AuthPayload {
        try await client.send("/api/auth/register", method: "POST", body: JSONBody.object(["name": name, "email": email, "password": password])).data
    }
    static func login(email: String, password: String) async throws -> AuthPayload {
        try await client.send("/api/auth/login", method: "POST", body: JSONBody.object(["email": email, "password": password])).data
    }
    static func logout() async throws {
        let _: APIEnvelope<[String: Bool]> = try await client.send("/api/auth/logout", method: "POST", body: JSONBody.object([:]))
    }
    static func me() async throws -> User {
        let env: APIEnvelope<UserPayload> = try await client.get("/api/auth/me")
        return env.data.user
    }

    // MARK: Profile
    static func updateProfile(_ body: JSONBody) async throws -> User {
        let env: APIEnvelope<UserPayload> = try await client.send("/api/profile", method: "PATCH", body: body)
        return env.data.user
    }
    static func deleteAccount(password: String) async throws {
        let _: APIEnvelope<[String: Bool]> = try await client.send("/api/profile", method: "DELETE", body: JSONBody.object(["password": password]))
    }
    static func colleges(query: String) async throws -> [College] {
        try await client.get("/api/colleges", query: ["q": query.isEmpty ? nil : query]).data
    }

    // MARK: Opportunities
    struct OpportunityQuery: Equatable {
        var text = ""
        var type: OpportunityType?
        var workMode: String?
        var location = ""
        var skills: [String] = []
        var verifiedOnly = false
        var includeClosed = false
        var campusOnly = false
        var deadlineWithinDays: Int?
        var sort = "relevance"

        var isFiltered: Bool {
            type != nil || workMode != nil || !location.isEmpty || !skills.isEmpty || verifiedOnly || includeClosed || campusOnly || deadlineWithinDays != nil
        }
    }

    static func opportunities(_ q: OpportunityQuery, page: Int, limit: Int = 20) async throws -> APIEnvelope<[Opportunity]> {
        try await client.get("/api/opportunities", query: [
            "q": q.text.isEmpty ? nil : q.text,
            "type": q.type?.rawValue,
            "workMode": q.workMode,
            "location": q.location.isEmpty ? nil : q.location,
            "skills": q.skills.isEmpty ? nil : q.skills.joined(separator: ","),
            "verifiedOnly": q.verifiedOnly ? "true" : nil,
            "includeClosed": q.includeClosed ? "true" : nil,
            "campusOnly": q.campusOnly ? "true" : nil,
            "deadlineWithinDays": q.deadlineWithinDays.map(String.init),
            "sort": q.sort,
            "page": String(page),
            "limit": String(limit),
        ])
    }
    static func opportunity(_ id: String) async throws -> Opportunity {
        try await client.get("/api/opportunities/\(id)").data
    }
    static func setSaved(_ id: String, saved: Bool) async throws {
        let _: APIEnvelope<[String: AnyCodableValue]> = try await client.send("/api/opportunities/\(id)/save", method: saved ? "POST" : "DELETE", body: Optional<JSONBody>.none)
    }
    static func saved() async throws -> [Opportunity] { try await client.get("/api/saved").data }
    static func matches() async throws -> APIEnvelope<[Opportunity]> { try await client.get("/api/matches") }
    static func checkEligibility(_ id: String, declarations: [String: Bool]) async throws -> EligibilityResult {
        try await client.send("/api/eligibility/check", method: "POST", body: JSONBody.object([
            "opportunityId": id,
            "declarations": declarations.mapValues { $0 as Any? },
        ])).data
    }

    // MARK: Applications
    static func applications(archived: Bool = false) async throws -> [TrackedApplication] {
        try await client.get("/api/applications", query: ["archived": archived ? "true" : "false"]).data
    }
    static func createApplication(_ body: JSONBody) async throws -> TrackedApplication {
        try await client.send("/api/applications", method: "POST", body: body).data
    }
    static func updateApplication(_ id: String, _ body: JSONBody) async throws -> TrackedApplication {
        try await client.send("/api/applications/\(id)", method: "PATCH", body: body).data
    }
    static func deleteApplication(_ id: String) async throws {
        let _: APIEnvelope<[String: AnyCodableValue]> = try await client.send("/api/applications/\(id)", method: "DELETE", body: Optional<JSONBody>.none)
    }

    // MARK: Home
    static func nextMoves() async throws -> [NextMove] { try await client.get("/api/me/next-moves").data }
    static func deadlines() async throws -> [DeadlineItem] { try await client.get("/api/me/deadlines").data }
    static func announcements() async throws -> APIEnvelope<[Announcement]> { try await client.get("/api/campus/announcements") }

    // MARK: Roadmap
    static func roadmap() async throws -> Roadmap? {
        let env: APIEnvelope<Roadmap?> = try await client.get("/api/roadmap")
        return env.data
    }
    static func generateRoadmap(goal: String, opportunityId: String?) async throws -> Roadmap {
        try await client.send("/api/ai/roadmap", method: "POST", body: JSONBody.object(["goal": goal, "opportunityId": opportunityId])).data
    }
    static func addMilestone(_ body: JSONBody) async throws -> Roadmap {
        try await client.send("/api/roadmap/milestones", method: "POST", body: body).data
    }
    static func updateMilestone(_ id: String, _ body: JSONBody) async throws -> Roadmap {
        try await client.send("/api/roadmap/milestones/\(id)", method: "PATCH", body: body).data
    }
    static func deleteMilestone(_ id: String) async throws -> Roadmap {
        try await client.send("/api/roadmap/milestones/\(id)", method: "DELETE", body: Optional<JSONBody>.none).data
    }

    // MARK: AI
    static func aiStatus() async throws -> AIStatus { try await client.get("/api/ai/status").data }
    static func chat(messages: [(role: String, content: String)], contextOpportunityId: String?) async throws -> ChatReply {
        try await client.send("/api/ai/chat", method: "POST", body: JSONBody.object([
            "messages": messages.map { ["role": $0.role, "content": $0.content] as [String: Any?] },
            "contextOpportunityId": contextOpportunityId,
        ])).data
    }
    static func explainMatch(_ id: String) async throws -> MatchExplanation {
        try await client.send("/api/ai/explain-match/\(id)", method: "POST", body: Optional<JSONBody>.none).data
    }
    static func draftEmail(opportunityId: String, tone: String, recipient: String?, notes: String?) async throws -> Draft {
        try await client.send("/api/ai/draft-email", method: "POST", body: JSONBody.object([
            "opportunityId": opportunityId, "tone": tone,
            "recipientName": recipient?.isEmpty == false ? recipient : nil,
            "extraContext": notes?.isEmpty == false ? notes : nil,
        ])).data
    }
    static func generateDocument(kind: String, opportunityId: String?, notes: String?) async throws -> Draft {
        try await client.send("/api/ai/resume", method: "POST", body: JSONBody.object([
            "kind": kind, "opportunityId": opportunityId,
            "extraContext": notes?.isEmpty == false ? notes : nil,
        ])).data
    }

    // MARK: Drafts
    static func drafts(opportunityId: String? = nil) async throws -> [Draft] {
        try await client.get("/api/drafts", query: ["opportunityId": opportunityId]).data
    }
    static func updateDraft(_ id: String, subject: String?, body: String, markReviewed: Bool) async throws -> Draft {
        try await client.send("/api/drafts/\(id)", method: "PATCH", body: JSONBody.object([
            "subject": subject, "body": body, "markReviewed": markReviewed ? true : nil,
        ])).data
    }
    static func deleteDraft(_ id: String) async throws {
        let _: APIEnvelope<[String: AnyCodableValue]> = try await client.send("/api/drafts/\(id)", method: "DELETE", body: Optional<JSONBody>.none)
    }

    // MARK: Admin
    static func adminColleges() async throws -> [College] { try await client.get("/api/admin/colleges").data }
    static func adminOpportunities() async throws -> [Opportunity] { try await client.get("/api/admin/opportunities").data }
    static func adminCreateOpportunity(_ body: JSONBody) async throws -> Opportunity {
        try await client.send("/api/admin/opportunities", method: "POST", body: body).data
    }
    static func adminUpdateOpportunity(_ id: String, _ body: JSONBody) async throws -> Opportunity {
        try await client.send("/api/admin/opportunities/\(id)", method: "PATCH", body: body).data
    }
    static func adminVerify(_ id: String, notes: String?) async throws -> Opportunity {
        try await client.send("/api/admin/opportunities/\(id)/verify", method: "POST", body: JSONBody.object(["sourceConfirmed": true, "notes": notes?.isEmpty == false ? notes : nil])).data
    }
    static func adminAnnouncements() async throws -> [Announcement] { try await client.get("/api/admin/announcements").data }
    static func adminCreateAnnouncement(_ body: JSONBody) async throws -> Announcement {
        try await client.send("/api/admin/announcements", method: "POST", body: body).data
    }
    static func adminUpdateAnnouncement(_ id: String, _ body: JSONBody) async throws -> Announcement {
        try await client.send("/api/admin/announcements/\(id)", method: "PATCH", body: body).data
    }
    static func adminMetrics() async throws -> AdminMetrics { try await client.get("/api/admin/metrics").data }
}

/// Decodes any JSON scalar; used for responses whose payload we ignore.
nonisolated enum AnyCodableValue: Decodable, Sendable {
    case string(String), bool(Bool), number(Double), null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else { self = .string((try? c.decode(String.self)) ?? "") }
    }
}
