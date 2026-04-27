import SwiftUI

/// Apple-style Privacy Report widget rendered as a SwiftUI overlay over the
/// new-tab wallpaper. Reads from `PrivacyReportStore.shared`; the whole
/// view re-renders when `snapshot` updates.
///
/// Layout mirrors Safari's macOS Privacy Report card:
///   ┌──────────────────────────────────────────────┐
///   │ [shield]            Last 30 days             │
///   │  Browse prevents   ┌─Trackers─┐ ┌─Websites─┐ │
///   │  trackers from     │    9     │ │   48%    │ │
///   │  profiling you.    └──────────┘ └──────────┘ │
///   │                    ┌─Most contacted tracker─┐│
///   │  Show More         │ google.com across 12   ││
///   │                    └────────────────────────┘│
///   └──────────────────────────────────────────────┘
struct PrivacyReportView: View {
    @State private var store = PrivacyReportStore.shared

    var body: some View {
        // Hide the widget entirely until the user has at least one browsing
        // history entry in the last 30 days. Showing a "0 trackers" card
        // before they've done anything is noise.
        if store.snapshot.hasBrowsingHistory {
            VStack(alignment: .leading, spacing: 12) {
                Text("Privacy Report")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 1)

                card
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(height: 350)
            .frame(maxHeight: .infinity, alignment: .top)
        } else {
            EmptyView()
        }
    }

    // MARK: - Card

    private var card: some View {
        HStack(alignment: .top, spacing: 24) {
            leftPanel
                .frame(width: 240)

            rightGrid
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial.opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: 6)
    }

    // MARK: - Left panel

    private var leftPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            ShieldIcon()
                .frame(width: 56, height: 64)

            Text("Blur prevents trackers from profiling you.")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color(nsColor: Colors.accentPrimary).opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }

    // MARK: - Right grid (3 stat cards)

    private var rightGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Last 30 days")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                statCard(
                    title: "Trackers prevented from profiling you",
                    value: "\(store.snapshot.trackerCount)"
                )

                statCard(
                    title: "Websites that contacted trackers",
                    value: "\(store.snapshot.pctSitesContacted ?? 0)%"
                )
            }

            mostContactedCard
        }
    }

    private func statCard(title: String, value: String) -> some View {
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

    @ViewBuilder
    private var mostContactedCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Most contacted tracker")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.secondary)

            if let top = store.snapshot.topTracker {
                Text("\(top.domain) was prevented from profiling you across \(top.acrossSitesCount) website\(top.acrossSitesCount == 1 ? "" : "s")")
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

// MARK: - Shield icon

/// Gradient-green shield. SF Symbol `shield.fill` filled with a vertical
/// gradient mirrors Safari's Privacy Report shield.
private struct ShieldIcon: View {
    var body: some View {
        Image(systemName: "staroflife.shield.fill")
            .resizable()
            .scaledToFit()
            .foregroundStyle(Color(nsColor: Colors.accentPrimary))
    }
}

// MARK: - Hosting helper

#if DEBUG
#Preview {
    ZStack {
        // Fake "wallpaper" so we can see the translucency
        LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
        PrivacyReportView()
    }
    .frame(width: 1100, height: 700)
}
#endif
