import Foundation

// MARK: - Envelope

nonisolated struct APIEnvelope<T: Decodable & Sendable>: Decodable, Sendable {
    let data: T
    let meta: PageMeta?
}

nonisolated struct PageMeta: Decodable, Sendable {
    let page: Int?
    let limit: Int?
    let total: Int?
    let totalPages: Int?
    let excludedIneligible: Int?
    let excludedRestricted: Int?
    let reason: String?
}

nonisolated struct APIErrorBody: Decodable, Sendable {
    struct Detail: Decodable, Sendable { let field: String; let message: String }
    struct Inner: Decodable, Sendable { let code: String; let message: String; let details: [Detail]? }
    let error: Inner
}

// MARK: - User & profile

nonisolated struct AuthPayload: Decodable, Sendable {
    let token: String
    let user: User
}

nonisolated struct UserPayload: Decodable, Sendable { let user: User }

nonisolated struct User: Codable, Sendable, Equatable {
    let id: String
    var email: String
    var name: String
    var role: String
    var adminCollegeIds: [String]
    var profile: Profile
    var notificationPrefs: NotificationPrefs
    var onboardingCompletedAt: Date?

    var isAdmin: Bool { role == "college_admin" || role == "platform_admin" }
    var firstName: String { name.split(separator: " ").first.map(String.init) ?? name }
}

nonisolated struct Profile: Codable, Sendable, Equatable {
    var collegeId: String?
    var collegeName: String?
    var degree: String?
    var branch: String?
    var currentYear: Int?
    var semester: Int?
    var graduationYear: Int?
    var cgpa: Double?
    var skills: [String]?
    var interests: [String]?
    var careerGoal: String?
    var headline: String?
    var projects: [Project]?
    var experience: [Experience]?
    var achievements: [String]?
    var preferredLocations: [String]?
    var workModes: [String]?
    var homeState: String?
    var annualFamilyIncomeINR: Double?
    var links: Links?
}

nonisolated struct Project: Codable, Sendable, Equatable, Identifiable {
    var id: String { _id ?? title }
    var _id: String?
    var title: String
    var description: String?
    var skills: [String]?
    var url: String?
}

nonisolated struct Experience: Codable, Sendable, Equatable, Identifiable {
    var id: String { _id ?? "\(role)-\(organization)" }
    var _id: String?
    var role: String
    var organization: String
    var description: String?
}

nonisolated struct Links: Codable, Sendable, Equatable {
    var github: String?
    var linkedin: String?
    var portfolio: String?
}

nonisolated struct NotificationPrefs: Codable, Sendable, Equatable {
    var deadlineReminders: Bool
    var reminderDaysBefore: Int
    var campusAnnouncements: Bool
}

nonisolated struct College: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let name: String
    let shortName: String?
    let city: String?
    let state: String?
    let website: String?
    let listed: Bool
}

// MARK: - Opportunities

nonisolated struct Money: Codable, Sendable, Equatable {
    let amount: Double?
    let currency: String?
    let period: String?
    let description: String?

    /// Formatted amount, or nil when the source did not state one.
    var formattedAmount: String? {
        guard let amount else { return nil }
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currency ?? "INR"
        f.locale = Locale(identifier: (currency ?? "INR") == "INR" ? "en_IN" : "en_US")
        f.maximumFractionDigits = 0
        let value = f.string(from: NSNumber(value: amount)) ?? "\(Int(amount))"
        switch period {
        case "per_year": return "\(value) / year"
        case "per_month": return "\(value) / month"
        case "one_time": return "\(value) one-time"
        case "total": return "\(value) total"
        default: return value
        }
    }
}

nonisolated struct OppLocation: Codable, Sendable, Equatable {
    let city: String?
    let state: String?
    let country: String?
    let isNationwide: Bool?
    let description: String?

    var display: String? {
        if let description, !description.isEmpty { return description }
        let parts = [city, state].compactMap { $0 }.filter { !$0.isEmpty }
        if !parts.isEmpty { return parts.joined(separator: ", ") }
        if isNationwide == true { return country == "India" || country == nil ? "Across India" : country }
        return nil
    }
}

nonisolated struct EligibilityRule: Codable, Sendable, Equatable {
    let key: String
    let kind: String
    let label: String
    let mandatory: Bool
    let values: [String]
    let numberValue: Double?
    let sourceExcerpt: String?
    let note: String?
}

nonisolated struct MatchFactor: Codable, Sendable, Equatable, Hashable {
    let factor: String
    let positive: Bool
    let detail: String
}

nonisolated struct MatchInfo: Codable, Sendable, Equatable {
    let score: Int
    let scoreLabel: String
    let eligibilityOverall: String
    let hardBlocked: Bool
    let audienceRestricted: Bool?
    let factors: [MatchFactor]
}

nonisolated struct TrackedRef: Codable, Sendable, Equatable {
    let id: String
    let status: String
    let archived: Bool
}

nonisolated struct SourceLink: Codable, Sendable, Equatable, Hashable {
    let label: String
    let url: String
}

nonisolated struct Opportunity: Codable, Sendable, Identifiable, Equatable {
    let id: String
    let title: String
    let organization: String
    let opportunityType: String
    let officialDescription: String?
    let summary: String?
    let summarySource: String?
    let sourceUrl: String
    let applicationUrl: String?
    let additionalSources: [SourceLink]?
    let sourceType: String
    let verificationStatus: String
    let lastVerifiedAt: Date?
    let verificationNotes: String?
    let isStale: Bool
    let availability: String
    let applicationOpensAt: Date?
    let deadline: Date?
    let deadlineNote: String?
    let eligibleDegrees: [String]
    let eligibleYears: [Int]
    let eligibleBranches: [String]
    let requiredSkills: [String]
    let preferredSkills: [String]
    let minimumCGPA: Double?
    let location: OppLocation?
    let workMode: String
    let award: Money?
    let stipend: Money?
    let duration: String?
    let eligibilityRules: [EligibilityRule]
    let requiredDocuments: [String]
    let tags: [String]
    let collegeId: String?
    let status: String
    let match: MatchInfo?
    var isSaved: Bool?
    var tracked: TrackedRef?

    var isCampus: Bool { collegeId != nil }
    var isVerified: Bool { verificationStatus == "verified" }
    var typeLabel: String { OpportunityType(rawValue: opportunityType)?.label ?? opportunityType.capitalized }
    var workModeLabel: String? {
        switch workMode {
        case "remote": "Remote"
        case "hybrid": "Hybrid"
        case "onsite": "On-site"
        default: nil
        }
    }
    var moneyLine: String? {
        if let a = award?.formattedAmount { return a }
        if let s = stipend?.formattedAmount { return s }
        return nil
    }
}

nonisolated enum OpportunityType: String, CaseIterable, Identifiable {
    case internship, scholarship, fellowship, research, competition, hackathon, job, program
    var id: String { rawValue }
    var label: String {
        switch self {
        case .internship: "Internship"
        case .scholarship: "Scholarship"
        case .fellowship: "Fellowship"
        case .research: "Research"
        case .competition: "Competition"
        case .hackathon: "Hackathon"
        case .job: "Job"
        case .program: "Programme"
        }
    }
    var symbol: String {
        switch self {
        case .internship: "briefcase"
        case .scholarship: "graduationcap"
        case .fellowship: "rosette"
        case .research: "flask"
        case .competition: "trophy"
        case .hackathon: "chevron.left.forwardslash.chevron.right"
        case .job: "building.2"
        case .program: "person.2.wave.2"
        }
    }
}

// MARK: - Eligibility

nonisolated struct EligibilityResult: Decodable, Sendable {
    let opportunityId: String
    let overall: String
    let counts: Counts
    let criteria: [Criterion]
    let caveats: [Caveat]
    let availability: String
    let disclaimer: String
    let checkedAt: String

    struct Counts: Decodable, Sendable { let met: Int; let unmet: Int; let unknown: Int }
}

nonisolated struct Criterion: Decodable, Sendable, Identifiable {
    var id: String { key }
    let key: String
    let kind: String
    let requirement: String
    let mandatory: Bool
    let studentValue: String?
    let status: String
    let explanation: String
    let nextStep: String?
    let sourceExcerpt: String?
    let restrictsAudience: Bool?
}

nonisolated struct Caveat: Decodable, Sendable, Identifiable {
    var id: String { code }
    let code: String
    let message: String
}

// MARK: - Applications

nonisolated enum ApplicationStatus: String, CaseIterable, Identifiable, Codable {
    case interested, preparing, ready_to_apply, applied, assessment, interview, offer, rejected, withdrawn
    var id: String { rawValue }
    var label: String {
        switch self {
        case .interested: "Interested"
        case .preparing: "Preparing"
        case .ready_to_apply: "Ready to apply"
        case .applied: "Applied"
        case .assessment: "Assessment"
        case .interview: "Interview"
        case .offer: "Offer"
        case .rejected: "Rejected"
        case .withdrawn: "Withdrawn"
        }
    }
    var symbol: String {
        switch self {
        case .interested: "star"
        case .preparing: "pencil.and.list.clipboard"
        case .ready_to_apply: "checkmark.seal"
        case .applied: "paperplane"
        case .assessment: "list.bullet.clipboard"
        case .interview: "person.2"
        case .offer: "gift"
        case .rejected: "xmark.circle"
        case .withdrawn: "arrow.uturn.backward"
        }
    }
    var isPreApply: Bool { [.interested, .preparing, .ready_to_apply].contains(self) }
    var isClosed: Bool { [.offer, .rejected, .withdrawn].contains(self) }
}

nonisolated struct StatusChange: Codable, Sendable, Hashable {
    let status: String
    let at: Date
}

nonisolated struct TrackedApplication: Codable, Sendable, Identifiable, Equatable {
    let id: String
    let opportunityId: String?
    var title: String
    var organization: String?
    var applicationUrl: String?
    var status: ApplicationStatus
    var statusHistory: [StatusChange]
    var notes: String
    var appliedAt: Date?
    var deadline: Date?
    var nextAction: String?
    var nextActionDue: Date?
    var archived: Bool
    let createdAt: Date
    let updatedAt: Date
}

// MARK: - Roadmap

nonisolated struct Roadmap: Decodable, Sendable, Equatable {
    let id: String
    let goal: String
    let summary: String?
    let generatedBy: String
    let targetOpportunityId: String?
    let progress: Progress
    var milestones: [Milestone]

    struct Progress: Decodable, Sendable, Equatable { let completed: Int; let total: Int }
}

nonisolated struct Milestone: Decodable, Sendable, Identifiable, Equatable {
    let id: String
    let title: String
    let purpose: String?
    let steps: [String]
    let skills: [String]
    let effortEstimate: String?
    let priority: String
    let order: Int
    let prerequisites: [String]
    let verifiedResources: [LearningResource]
    let suggestedResources: [SuggestedResource]
    let projectIdeas: [String]
    let targetDate: Date?
    let status: String
    let completedAt: Date?
    let source: String
}

nonisolated struct LearningResource: Codable, Sendable, Identifiable, Equatable {
    let id: String
    let title: String
    let provider: String
    let url: String
    let skills: [String]
    let cost: String
    let description: String?
    let verifiedAt: Date
}

nonisolated struct SuggestedResource: Codable, Sendable, Equatable, Hashable {
    let title: String
    let note: String?
}

// MARK: - Campus

nonisolated struct Announcement: Decodable, Sendable, Identifiable, Equatable {
    let id: String
    let collegeId: String
    let collegeName: String?
    let title: String
    let body: String
    let category: String
    let sourceUrl: String?
    let linkedOpportunityId: String?
    let status: String
    let publishedAt: Date?
    let expiresAt: Date?
    let publisherName: String?
    let updatedAt: Date
}

// MARK: - Drafts

nonisolated struct Draft: Decodable, Sendable, Identifiable, Equatable {
    let id: String
    let opportunityId: String?
    let kind: String
    let title: String?
    var subject: String?
    var body: String
    let generatedBy: String
    let missingInformation: [String]
    var reviewedAt: Date?
    let updatedAt: Date

    var kindLabel: String {
        switch kind {
        case "email": "Application email"
        case "cover_letter": "Cover letter"
        case "resume": "Resume"
        case "resume_summary": "Resume summary"
        default: kind.capitalized
        }
    }
}

// MARK: - Next moves & deadlines

nonisolated struct NextMove: Decodable, Sendable, Identifiable, Equatable {
    var id: String { "\(kind)-\(target.id ?? title)" }
    let kind: String
    let title: String
    let detail: String
    let reason: String
    let dueAt: Date?
    let target: Target

    struct Target: Decodable, Sendable, Equatable {
        let type: String
        let id: String?
    }
}

nonisolated struct DeadlineItem: Decodable, Sendable, Identifiable, Equatable {
    var id: String { "\(kind)-\(applicationId ?? opportunityId ?? title)-\(date.timeIntervalSince1970)" }
    let kind: String
    let date: Date
    let title: String
    let organization: String?
    let applicationId: String?
    let opportunityId: String?
    let overdue: Bool?
}

// MARK: - AI

nonisolated struct AIStatus: Decodable, Sendable { let available: Bool; let model: String? }

nonisolated struct ChatReply: Decodable, Sendable {
    let reply: String
    let citations: [Citation]
    let proposedActions: [ProposedAction]
    let toolsUsed: [String]
}

nonisolated struct Citation: Decodable, Sendable, Hashable, Identifiable {
    var id: String { opportunityId }
    let opportunityId: String
    let title: String
    let sourceUrl: String
    let verificationStatus: String
}

nonisolated struct ProposedAction: Decodable, Sendable, Identifiable, Hashable {
    let id: String
    let type: String
    let opportunityId: String?
    let title: String?
    let label: String
    let nextAction: String?
    let goal: String?
}

nonisolated struct MatchExplanation: Decodable, Sendable {
    let explanation: String
    let nextSteps: [String]
}

// MARK: - Admin

nonisolated struct AdminMetrics: Decodable, Sendable {
    let generatedAt: String
    let note: String
    let studentsOnNaviq: SuppressedCount
    let announcements: [String: Int]
    let listings: [Listing]

    struct Listing: Decodable, Sendable, Identifiable {
        var id: String { opportunityId }
        let opportunityId: String
        let title: String
        let status: String
        let verificationStatus: String
        let saves: SuppressedCount
        let tracked: SuppressedCount
    }
}

nonisolated struct SuppressedCount: Decodable, Sendable {
    let count: Int?
    let suppressed: Bool

    var display: String { suppressed ? "Fewer than 3" : "\(count ?? 0)" }
}

nonisolated struct Empty: Decodable, Sendable {}
