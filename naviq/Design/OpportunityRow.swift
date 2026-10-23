import SwiftUI

/// Opportunity card: a colour block per category, bold title, the verified
/// facts, and the top "why it matches" reason.
struct OpportunityRow: View {
    let opportunity: Opportunity
    var index: Int?
    var showReason = true

    private var type: OpportunityType? { OpportunityType(rawValue: opportunity.opportunityType) }
    private var block: Color { NaviqColor.block(for: opportunity.opportunityType) }

    var body: some View {
        VStack(alignment: .leading, spacing: NaviqSpacing.m) {
            HStack(alignment: .center, spacing: NaviqSpacing.m) {
                IconBadge(systemImage: type?.symbol ?? "sparkles", fill: block, foreground: NaviqColor.ink, size: 46)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(opportunity.typeLabel)
                            .font(.system(.caption, design: .rounded).weight(.heavy))
                            .foregroundStyle(NaviqColor.ink)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3)
                            .background { Capsule().fill(block) }
                        if opportunity.isCampus {
                            Text("Campus")
                                .font(.system(.caption, design: .rounded).weight(.heavy))
                                .foregroundStyle(NaviqColor.coral)
                        }
                    }
                }
                Spacer(minLength: 0)
                if opportunity.isSaved == true {
                    Image(systemName: "bookmark.fill")
                        .foregroundStyle(NaviqColor.accent)
                        .accessibilityLabel("Saved")
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(opportunity.title)
                    .font(.system(.headline, design: .rounded).weight(.heavy))
                    .foregroundStyle(NaviqColor.ink)
                    .multilineTextAlignment(.leading)
                Text(opportunity.organization)
                    .font(NaviqFont.callout)
                    .foregroundStyle(NaviqColor.inkSecondary)
                    .multilineTextAlignment(.leading)
            }

            FlowLayout(spacing: 8) {
                factPill { DeadlineLabel(availability: opportunity.availability, deadline: opportunity.deadline) }
                if let money = opportunity.moneyLine {
                    factPill {
                        Label(money, systemImage: "indianrupeesign.circle.fill")
                            .font(NaviqFont.meta.weight(.semibold))
                            .foregroundStyle(NaviqColor.ink)
                    }
                }
                factPill { VerificationLabel(status: opportunity.verificationStatus, lastVerifiedAt: opportunity.lastVerifiedAt, isStale: opportunity.isStale, compact: true) }
            }

            if showReason, let reason {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: reason.positive ? "sparkles" : "exclamationmark.circle.fill")
                        .foregroundStyle(reason.positive ? NaviqColor.jade : NaviqColor.amber)
                    Text(reason.detail)
                        .foregroundStyle(NaviqColor.ink)
                        .multilineTextAlignment(.leading)
                }
                .font(NaviqFont.meta)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background { RoundedRectangle(cornerRadius: 14, style: .continuous).fill(reason.positive ? NaviqColor.jadeSoft : NaviqColor.amberSoft) }
            }
        }
        .naviqCard()
        .contentShape(RoundedRectangle(cornerRadius: NaviqSpacing.radius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens details")
    }

    private func factPill<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        content()
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background { Capsule().fill(NaviqColor.surfaceSunken) }
    }

    private var reason: MatchFactor? {
        guard let match = opportunity.match else { return nil }
        if let audience = match.factors.first(where: { $0.factor == "audience" }) { return audience }
        if match.hardBlocked { return match.factors.first { !$0.positive && $0.factor == "education" } ?? match.factors.first { !$0.positive } }
        return match.factors.first { $0.positive }
    }
}
