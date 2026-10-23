import Foundation

/// Editable copy of the student's profile, shared by onboarding and Edit
/// Profile. Converts to the PATCH body; empty fields are sent as null so
/// "unknown" stays unknown instead of becoming an empty string.
struct ProfileDraft: Equatable {
    var name = ""
    var college: College?
    var customCollegeName = ""
    var degree = ""
    var branch = ""
    var currentYear: Int?
    var graduationYear: Int?
    var cgpaText = ""
    var skills: [String] = []
    var interests: [String] = []
    var careerGoal = ""
    var headline = ""
    var workModes: Set<String> = []
    var locations: [String] = []
    var homeState = ""
    var incomeText = ""
    var achievements: [String] = []
    var projects: [Project] = []
    var github = ""
    var linkedin = ""
    var portfolio = ""
    var collegeChanged = false

    static let degrees = ["B.Tech", "B.E.", "BCA", "B.Sc", "BS", "B.Com", "BA", "BBA", "B.Arch", "B.Pharm", "MBBS", "M.Tech", "M.E.", "MCA", "M.Sc", "MBA", "Diploma", "Integrated", "Other"]
    static let branchSuggestions = ["Computer Science and Engineering", "Information Technology", "Electronics and Communication", "Electrical Engineering", "Mechanical Engineering", "Civil Engineering", "AI & Machine Learning", "Data Science", "Cybersecurity"]
    static let skillSuggestions = ["Python", "Java", "C++", "JavaScript", "Linux", "Networking", "SQL", "Git", "Web Security", "Machine Learning", "Swift", "React"]
    static let interestSuggestions = ["Cybersecurity", "Research", "Scholarships", "Internships", "Open Source", "Hackathons", "Web Development", "AI/ML", "Government programmes"]
    static let states = ["Andhra Pradesh", "Assam", "Bihar", "Chhattisgarh", "Delhi", "Goa", "Gujarat", "Haryana", "Himachal Pradesh", "Jammu and Kashmir", "Jharkhand", "Karnataka", "Kerala", "Madhya Pradesh", "Maharashtra", "Odisha", "Punjab", "Rajasthan", "Tamil Nadu", "Telangana", "Uttar Pradesh", "Uttarakhand", "West Bengal", "Other"]

    init() {}

    init(user: User) {
        let p = user.profile
        name = user.name
        if let id = p.collegeId, let n = p.collegeName {
            college = College(id: id, name: n, shortName: nil, city: nil, state: nil, website: nil, listed: true)
        }
        degree = p.degree ?? ""
        branch = p.branch ?? ""
        currentYear = p.currentYear
        graduationYear = p.graduationYear
        cgpaText = p.cgpa.map { String(format: "%.2f", $0) } ?? ""
        skills = p.skills ?? []
        interests = p.interests ?? []
        careerGoal = p.careerGoal ?? ""
        headline = p.headline ?? ""
        workModes = Set(p.workModes ?? [])
        locations = p.preferredLocations ?? []
        homeState = p.homeState ?? ""
        incomeText = p.annualFamilyIncomeINR.map { String(Int($0)) } ?? ""
        achievements = p.achievements ?? []
        projects = p.projects ?? []
        github = p.links?.github ?? ""
        linkedin = p.links?.linkedin ?? ""
        portfolio = p.links?.portfolio ?? ""
    }

    var cgpa: Double? { Double(cgpaText.replacingOccurrences(of: ",", with: ".")) }
    var income: Double? { Double(incomeText.filter(\.isNumber)) }
    var cgpaInvalid: Bool { !cgpaText.isEmpty && (cgpa == nil || cgpa! < 0 || cgpa! > 10) }

    func body(completeOnboarding: Bool = false) -> JSONBody {
        var profile: [String: Any?] = [
            "degree": degree.nilIfEmpty ?? "",
            "branch": branch.nilIfEmpty ?? "",
            "currentYear": currentYear.map { $0 as Any } ?? NSNull(),
            "graduationYear": graduationYear.map { $0 as Any } ?? NSNull(),
            "cgpa": cgpaInvalid ? NSNull() : (cgpa.map { $0 as Any } ?? NSNull()),
            "skills": skills,
            "interests": interests,
            "careerGoal": careerGoal.trimmed,
            "headline": headline.trimmed,
            "workModes": Array(workModes).sorted(),
            "preferredLocations": locations,
            "homeState": homeState.nilIfEmpty.map { $0 as Any } ?? NSNull(),
            "annualFamilyIncomeINR": income.map { $0 as Any } ?? NSNull(),
            "achievements": achievements,
            "projects": projects.map { p -> [String: Any?] in
                ["title": p.title, "description": p.description ?? "", "skills": p.skills ?? [], "url": p.url ?? ""]
            },
            "links": ["github": github.trimmed, "linkedin": linkedin.trimmed, "portfolio": portfolio.trimmed] as [String: Any?],
        ]
        if collegeChanged {
            if let college { profile["collegeId"] = college.id }
            else if let custom = customCollegeName.nilIfEmpty { profile["customCollegeName"] = custom }
        }
        var root: [String: Any?] = ["profile": profile]
        if let n = name.nilIfEmpty { root["name"] = n }
        if completeOnboarding { root["completeOnboarding"] = true }
        return JSONBody.object(root)
    }
}
