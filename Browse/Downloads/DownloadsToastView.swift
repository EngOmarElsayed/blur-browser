import SwiftUI
import AppKit

struct DownloadsToastView: View {
    let items: [DownloadItem]
    var onDismiss: () -> Void
    var onCancel: (UUID) -> Void
    var onPause: (UUID) -> Void
    var onResume: (UUID) -> Void
    var onReveal: (URL) -> Void

    private static let maxVisible = 3

    private var visibleItems: [DownloadItem] {
        Array(items.prefix(Self.maxVisible))
    }

    private var hiddenCount: Int {
        max(0, items.count - Self.maxVisible)
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack(alignment: .center) {
                Text("Downloads")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color(nsColor: Colors.foregroundPrimary))

                trailingButton
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .frame(height: 20)
            }

            VStack(spacing: 12) {
                ForEach(Array(visibleItems.enumerated()), id: \.element.id) { offset, item in
                    DownloadRow(
                        item: item,
                        onCancel: { onCancel(item.id) },
                        onPause: { onPause(item.id) },
                        onResume: { onResume(item.id) },
                        onReveal: onReveal
                    )
                    .frame(height: 50)

                    if offset < visibleItems.count - 1 { Divider().padding(.horizontal, -12) }
                }
            }

            if hiddenCount > 0 {
                Text("+\(hiddenCount) more")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(nsColor: Colors.foregroundSecondary))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
            }
        }
        .padding(12)
        .frame(width: 280)
        .background(Color(nsColor: Colors.surfacePrimary))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color(nsColor: Colors.borderLight).opacity(0.6), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 16, x: 0, y: 4)
    }

    // MARK: - Trailing button — always "dismiss from toast"
    // For in-progress downloads, canceling is available via the hover overlay.
    // The X here just removes the row from the toast (keeps the underlying
    // DownloadItem in the store — user can still see it in the sidebar).

    @ViewBuilder
    private var trailingButton: some View {
        Button(action: onDismiss) {
            Image(systemName: "minus")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color(nsColor: Colors.foregroundMuted))
                .frame(width: 16, height: 16)
        }
        .buttonStyle(.plain)
        .help("Hide downloads")
    }
}

// MARK: - Row

private struct DownloadRow: View {
    let item: DownloadItem
    let onCancel: () -> Void
    let onPause: () -> Void
    let onResume: () -> Void
    let onReveal: (URL) -> Void

    @State private var isProgressHovered = false

    var body: some View {
        HStack(spacing: 10) {
            statusIcon
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center) {
                    Text(item.fileName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(nsColor: Colors.foregroundPrimary))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .layoutPriority(1)

                    if isProgressHovered && (item.status == .paused || item.status == .inProgress) {
                        HStack(spacing: 6) {
                            hoverButton(
                                systemName: item.status == .inProgress ? "pause.fill": "play.fill",
                                color: item.status == .inProgress ? .yellow: .green,
                                label: "Pause",
                                action: item.status == .inProgress ? onPause: onResume
                            )

                            hoverButton(systemName: "xmark", color: .red, label: "Cancel", action: onCancel)
                        }
                        .padding(.horizontal, 2)
                    }
                }

                statusLine
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
        .onHover { isProgressHovered = $0 }
        .onTapGesture {
            // Clicking a completed row reveals it in Finder
            if item.status == .completed, let url = item.localFileURL {
                onReveal(url)
            }
        }
    }

    // MARK: - Leading icon (state-dependent)

    @ViewBuilder
    private var statusIcon: some View {
        switch item.status {
        case .completed:
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.15))
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.green)
            }
        case .failed:
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.15))
                Image(systemName: "exclamationmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.red)
            }
        case .cancelled:
            ZStack {
                Circle()
                    .fill(Color(nsColor: Colors.surfaceSecondary))
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(nsColor: Colors.foregroundMuted))
            }
        case .inProgress, .paused:
            fileIcon
        }
    }

    private var fileIcon: some View {
        let ext = (item.fileName as NSString).pathExtension
        let nsImage = !ext.isEmpty
            ? NSWorkspace.shared.icon(forFileType: ext)
            : (NSImage(systemSymbolName: "doc", accessibilityDescription: nil) ?? NSImage())
        return Image(nsImage: nsImage)
            .resizable()
            .aspectRatio(contentMode: .fit)
    }

    // MARK: - Status line (progress bar OR text)

    @ViewBuilder
    private var statusLine: some View {
        switch item.status {
        case .inProgress:
            progressBarSection
            Text(progressText)
                .font(.system(size: 10))
                .foregroundStyle(Color(nsColor: Colors.foregroundSecondary))

        case .paused:
            progressBarSection
            Text("Paused — \(progressText)")
                .font(.system(size: 10))
                .foregroundStyle(Color(nsColor: Colors.foregroundSecondary))
        case .completed:
            Text("Downloaded — \(formattedFullSize)")
                .font(.system(size: 10))
                .foregroundStyle(Color(nsColor: Colors.foregroundSecondary))
        case .failed:
            Text("Download failed")
                .font(.system(size: 10))
                .foregroundStyle(.red)
        case .cancelled:
            Text("Cancelled")
                .font(.system(size: 10))
                .foregroundStyle(Color(nsColor: Colors.foregroundMuted))
        }
    }

    /// Progress bar with a hover overlay that shows Pause + Cancel buttons
    private var progressBarSection: some View {
        // Background + fill
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(nsColor: Colors.surfaceSecondary))

                RoundedRectangle(cornerRadius: 3)
                    .fill(item.status == .paused
                          ? Color(nsColor: Colors.foregroundMuted)
                          : Color(nsColor: Colors.accentPrimary))
                    .frame(width: max(0, geo.size.width * CGFloat(item.fractionComplete ?? 0)))
                    .animation(.easeOut(duration: 0.2), value: item.completedBytes)
            }
        }
        .frame(height: 6)
    }

    private func hoverButton(systemName: String, color: Color, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(color)
        }
        .buttonStyle(.plain)
        .help(label)
    }

    // MARK: - Formatters

    private var progressText: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        let completed = formatter.string(fromByteCount: item.completedBytes)
        if let total = item.totalBytes, total > 0 {
            let totalStr = formatter.string(fromByteCount: total)
            return "\(completed) of \(totalStr)"
        }
        return completed
    }

    private var formattedFullSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        if let total = item.totalBytes, total > 0 {
            return formatter.string(fromByteCount: total)
        }
        return formatter.string(fromByteCount: item.completedBytes)
    }
}
