//
//  PrivacyReportCard.swift
//  Blur-Browser
//
//  Created by Omar Elsayed on 25/06/2026.
//

import SwiftUI

struct PrivacyReportCard: View {
    let privacySnapshot: PrivacyReportSnapshot

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            LeftShieldGrid()

            RightGridItems(privacySnapshot: privacySnapshot)
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        )
    }
}

// MARK: - LeftShieldGrid
struct LeftShieldGrid: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "staroflife.shield.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color(hex: "#069605"))
                .frame(width: 56, height: 64)

            Text("Blur prevents trackers from profiling you.")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color(nsColor: .black))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 240)
    }
}

// MARK: - RightGridItems
struct RightGridItems: View {
    let privacySnapshot: PrivacyReportSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Last 30 days")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                PrivacyStatusCard(
                    title: "Trackers prevented from profiling you",
                    value: "\(privacySnapshot.trackerCount)"
                )

                PrivacyStatusCard(
                    title: "Websites that contacted trackers",
                    value: "\(privacySnapshot.pctSitesContacted ?? 0)%"
                )
            }

            PrivacyMostContactedCard(
                topTracker: privacySnapshot.topTracker
            )
        }
    }

    // MARK: - SubViews
    struct PrivacyStatusCard: View {
        let title: String, value: String
        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: true)

                Text(value)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Color(nsColor: Colors.accentPrimary))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.white.opacity(0.55))
            )
        }
    }

    struct PrivacyMostContactedCard: View {
        let topTracker: TopTracker?
        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("Most contacted tracker")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)

                if let topTracker {
                    Text("\(topTracker.domain) was prevented from profiling you across \(topTracker.acrossSitesCount) website\(topTracker.acrossSitesCount == 1 ? "" : "s")")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color(nsColor: Colors.accentPrimary))
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Browse a few sites — we'll show what we blocked here.")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.white.opacity(0.55))
            )
        }
    }
}
