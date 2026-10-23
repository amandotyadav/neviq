import SwiftUI

/// Editorial index row for an opportunity: type kicker, serif title,
/// organisation, verified facts, and the top "why it matches" reason.
struct OpportunityRow: View {
    let opportunity: Opportunity
    var index: Int?
    var showReason = true

    var body: some View {
        HStack(alignment: .top, spacing: NaviqSpacing.m) {
            if let index {
                Text(String(format: "%02d", index))
                    .font(.system(.callout, design: .serif).weight(.semibold).monospacedDigit())
                    .foregroundStyle(NaviqColor.inkTertiary)
                    .frame(width: 26, alignment: .leading)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(opportunity.typeLabel).kickerStyle(NaviqColor.accent)
                    if opportunity.isCampus {
                        Text("· Campus").kickerStyle(NaviqColor.coral)
                    }
                    Spacer(minLength: 0)
                    if opportunity.isSaved == true {
                        Image(systemName: "bookmark.fill")
                            .font(.caption)
                            .foregroundStyle(NaviqColor.ink)
                            .accessibilityLabel("Saved")
                    }
                }
                Text(opportunity.title)
                    .font(NaviqFont.cardTitle)
                    .foregroundStyle(NaviqColor.ink)
                    .multilineTextAlignment(.leading)
                Text(opportunity.organization)
                    .font(.subheadline)
                    .foregroundStyle(NaviqColor.inkSecondary)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: NaviqSpacing.m) { metaItems }
                    VStack(alignment: .leading, spacing: 4) { metaItems }
                }
                .padding(.top, 2)

                if showReason, let reason {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: reason.positive ? "arrow.up.right" : "exclamationmark.circle")
                            .foregroundStyle(reason.positive ? NaviqColor.jade : NaviqColor.amber)
                        Text(reason.detail)
                            .foregroundStyle(NaviqColor.inkSecondary)
                    }
                    .font(.footnote)
                    .padding(.top, 2)
                }
            }
        }
        .padding(.vertical, NaviqSpacing.m)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens details")
    }

    @ViewBuilder private var metaItems: some View {
        DeadlineLabel(availability: opportunity.availability, deadline: opportunity.deadline)
        if let money = opportunity.moneyLine {
            Label(money, systemImage: "indianrupeesign")
                .font(NaviqFont.meta)
                .foregroundStyle(NaviqColor.inkSecondary)
                .labelStyle(.titleOnly)
        }
        VerificationLabel(status: opportunity.verificationStatus, lastVerifiedAt: opportunity.lastVerifiedAt, isStale: opportunity.isStale, compact: true)
    }

    private var reason: MatchFactor? {
        guard let match = opportunity.match else { return nil }
        if let audience = match.factors.first(where: { $0.factor == "audience" }) { return audience }
        if match.hardBlocked { return match.factors.first { !$0.positive && $0.factor == "education" } ?? match.factors.first { !$0.positive } }
        return match.factors.first { $0.positive }
    }
}
