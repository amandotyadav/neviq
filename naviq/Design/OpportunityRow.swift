import SwiftUI

/// Editorial list row: numbered, serif title, ruled metadata, no container.
/// Rows are separated by hairlines supplied by the list that hosts them.
struct OpportunityRow: View {
    let opportunity: Opportunity
    var index: Int?
    var showReason = true

    private var type: OpportunityType? { OpportunityType(rawValue: opportunity.opportunityType) }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            if let index {
                Text(String(format: "%02d", index))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(NaviqColor.accent)
                    .frame(width: 22, alignment: .leading)
                    .padding(.top, 3)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Image(systemName: type?.symbol ?? "doc.text").font(.caption)
                    Text(opportunity.typeLabel).eyebrowStyle()
                    if opportunity.isCampus { Text("· Campus").eyebrowStyle(NaviqColor.coral) }
                    if opportunity.isSaved == true {
                        Image(systemName: "bookmark.fill").font(.caption).foregroundStyle(NaviqColor.accent)
                            .accessibilityLabel("Saved")
                    }
                }
                .foregroundStyle(NaviqColor.inkSecondary)

                Text(opportunity.title)
                    .itemTitleStyle()
                    .foregroundStyle(NaviqColor.ink)
                    .multilineTextAlignment(.leading)
                    .lineLimit(4)
                Text(opportunity.organization)
                    .font(.subheadline)
                    .foregroundStyle(NaviqColor.inkSecondary)
                    .multilineTextAlignment(.leading)

                FlowLayout(spacing: 20) {
                    fact("Source") {
                        VerificationLabel(status: opportunity.verificationStatus, lastVerifiedAt: opportunity.lastVerifiedAt, isStale: opportunity.isStale, compact: true)
                    }
                    if let money = opportunity.moneyLine {
                        fact(opportunity.award != nil ? "Award" : "Stipend") {
                            Text(money).font(.caption.weight(.medium)).foregroundStyle(NaviqColor.ink)
                        }
                    }
                    if opportunity.availability != "open", let label = availabilityText {
                        fact("Status") { Text(label).font(.caption.weight(.medium)).foregroundStyle(NaviqColor.inkSecondary) }
                    }
                }
                .padding(.top, 2)

                if showReason, let reason {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: reason.positive ? "checkmark" : "exclamationmark.circle")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(reason.positive ? NaviqColor.jade : NaviqColor.amber)
                        Text(reason.detail)
                            .font(.system(.footnote, design: .serif).italic())
                            .foregroundStyle(NaviqColor.inkSecondary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                    }
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
            DeadlineIndicator(date: opportunity.deadline, availability: opportunity.availability)
                .frame(minWidth: 52, alignment: .trailing)
        }
        .padding(.vertical, 16)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens details")
    }

    private var availabilityText: String? {
        switch opportunity.availability {
        case "closed": "Closed"
        case "upcoming": "Opens soon"
        case "unknown": opportunity.deadline == nil ? "Dates not published" : nil
        default: nil
        }
    }

    private func fact<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 9.5, weight: .semibold)).tracking(0.8).textCase(.uppercase).foregroundStyle(NaviqColor.inkTertiary)
            content()
        }
    }

    private var reason: MatchFactor? {
        guard let match = opportunity.match else { return nil }
        if let audience = match.factors.first(where: { $0.factor == "audience" }) { return audience }
        if match.hardBlocked { return match.factors.first { !$0.positive && $0.factor == "education" } ?? match.factors.first { !$0.positive } }
        return match.factors.first { $0.positive }
    }
}

/// The one dominant element on a screen: a deep-forest panel for a genuinely
/// available, verified opportunity.
struct OpportunityFeature: View {
    let opportunity: Opportunity
    var eyebrow = "Featured"

    private var reason: MatchFactor? { opportunity.match?.factors.first { $0.positive } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(eyebrow).eyebrowStyle(NaviqColor.onDeepForest.opacity(0.7))
                Spacer()
                Text(opportunity.typeLabel).eyebrowStyle(NaviqColor.onDeepForest.opacity(0.7))
            }
            Text(opportunity.title)
                .font(.system(size: 26, weight: .semibold, design: .serif))
                .tracking(-0.4)
                .foregroundStyle(NaviqColor.onDeepForest)
                .multilineTextAlignment(.leading)
                .minimumScaleFactor(0.75)
            Text(opportunity.organization)
                .font(.subheadline)
                .foregroundStyle(NaviqColor.onDeepForest.opacity(0.78))
                .multilineTextAlignment(.leading)

            if let reason {
                Text(reason.detail)
                    .font(.system(.callout, design: .serif).italic())
                    .foregroundStyle(NaviqColor.onDeepForest.opacity(0.92))
                    .multilineTextAlignment(.leading)
            }

            Rectangle().fill(NaviqColor.onDeepForest.opacity(0.25)).frame(height: 1)

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Deadline").eyebrowStyle(NaviqColor.onDeepForest.opacity(0.6))
                    Text(Dates.deadlinePhrase(opportunity.deadline).replacingOccurrences(of: "Closes ", with: "").capitalized)
                        .font(.system(.title3, design: .serif).weight(.semibold))
                        .foregroundStyle(NaviqColor.onDeepForest)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    if let money = opportunity.moneyLine {
                        Text(opportunity.award != nil ? "Award" : "Stipend").eyebrowStyle(NaviqColor.onDeepForest.opacity(0.6))
                        Text(money).font(.subheadline.weight(.semibold)).foregroundStyle(NaviqColor.onDeepForest)
                    }
                }
            }
            HStack(spacing: 6) {
                Image(systemName: opportunity.isVerified && !opportunity.isStale ? "checkmark.seal" : "exclamationmark.triangle")
                Text(opportunity.isVerified && !opportunity.isStale ? "Verified against the official source" : "Check the official source before relying on this")
                Spacer()
                Image(systemName: "arrow.right")
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(NaviqColor.onDeepForest.opacity(0.9))
        }
        .padding(NaviqSpacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { RoundedRectangle(cornerRadius: 6, style: .continuous).fill(NaviqColor.deepForest) }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens details")
    }
}
