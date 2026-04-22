import SwiftUI
import AppKit

struct DownloadsPanelView: View {
    let store: DownloadStore
    var onCancel: (UUID) -> Void
    var onPause: (UUID) -> Void = { _ in }
    var onResume: (UUID) -> Void = { _ in }
    @State private var searchText = ""

    private var filtered: [DownloadItem] {
        searchText.trimmingCharacters(in: .whitespaces).isEmpty
            ? store.items
            : store.search(searchText)
    }

    private var groups: [(String, [DownloadItem])] {
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday)!
        let last7Days = calendar.date(byAdding: .day, value: -7, to: startOfToday)!

        var today: [DownloadItem] = []
        var yesterday: [DownloadItem] = []
        var last7: [DownloadItem] = []
        var older: [DownloadItem] = []

        for item in filtered {
            if item.startedAt >= startOfToday { today.append(item) }
            else if item.startedAt >= startOfYesterday { yesterday.append(item) }
            else if item.startedAt >= last7Days { last7.append(item) }
            else { older.append(item) }
        }

        var result: [(String, [DownloadItem])] = []
        if !today.isEmpty     { result.append(("Today", today)) }
        if !yesterday.isEmpty { result.append(("Yesterday", yesterday)) }
        if !last7.isEmpty     { result.append(("Last 7 Days", last7)) }
        if !older.isEmpty     { result.append(("Older", older)) }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if filtered.isEmpty {
                emptyState
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(groups, id: \.0) { group in
                            Section(header: sectionHeader(group.0)) {
                                ForEach(group.1) { item in
                                    DownloadRow(
                                        item: item,
                                        onCancel: { onCancel(item.id) },
                                        onPause: { onPause(item.id) },
                                        onResume: { onResume(item.id) }
                                    )
                                    .contextMenu { contextMenu(for: item) }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 6)
                }
                .overlay(alignment: .bottomTrailing) {
                    Button {
                        store.removeAll()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundStyle(Color(nsColor: Colors.foregroundMuted))
                    }
                    .buttonStyle(.plain)
                    .help("Clear all downloads")
                    .padding([.trailing, .bottom], 4)
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            Text("Downloads")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(nsColor: Colors.foregroundMuted))
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(nsColor: Colors.foregroundSecondary))
                TextField("Search downloads...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(nsColor: Colors.foregroundSecondary))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(nsColor: Colors.surfacePrimary).opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(nsColor: Colors.borderLight).opacity(0.5), lineWidth: 1)
            )
            .padding(.horizontal, 10)
        }
        .padding(.vertical, 8)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Color(nsColor: Colors.foregroundMuted))
            .tracking(0.5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .background(Color.clear)
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 6) {
            Spacer().frame(height: 30)
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Color(nsColor: Colors.foregroundMuted).opacity(0.6))
            Text("No downloads yet")
                .font(.system(size: 12))
                .foregroundStyle(Color(nsColor: Colors.foregroundMuted).opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func contextMenu(for item: DownloadItem) -> some View {
        if item.status == .completed, let url = item.localFileURL {
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            Button("Open") {
                NSWorkspace.shared.open(url)
            }
        }
        Button("Copy Download Link") {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(item.sourceURL, forType: .string)
        }
        Divider()
        Button("Remove from List") {
            store.removeDownload(id: item.id)
        }
        if item.status == .completed, let url = item.localFileURL {
            Button("Delete File") {
                try? FileManager.default.removeItem(at: url)
                store.removeDownload(id: item.id)
            }
        }
    }
}

// MARK: - Row

private struct DownloadRow: View {
    let item: DownloadItem
    let onCancel: () -> Void
    let onPause: () -> Void
    let onResume: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            fileIcon
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .center, spacing: 4) {
                    Text(item.fileName)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .font(.system(size: 13))
                        .foregroundStyle(Color(nsColor: Colors.foregroundPrimary))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .layoutPriority(1)

                    if (item.status == .paused || item.status == .inProgress) && isHovered { trailingAccessory }
                }

                statusLine
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color(nsColor: Colors.surfacePrimary).opacity(0.4) : .clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture {
            if item.status == .completed, let url = item.localFileURL {
                NSWorkspace.shared.open(url)
            }
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

    @ViewBuilder
    private var statusLine: some View {
        switch item.status {
        case .inProgress:
            progressLine
        case .paused:
            progressLine
        case .completed:
            Text(fileSizeString)
                .font(.system(size: 10))
                .foregroundStyle(Color(nsColor: Colors.foregroundSecondary))
        case .failed:
            Text("Failed")
                .font(.system(size: 10))
                .foregroundStyle(.red)
        case .cancelled:
            Text("Cancelled")
                .font(.system(size: 10))
                .foregroundStyle(Color(nsColor: Colors.foregroundMuted))
        }
    }

    private var progressLine: some View {
        VStack(alignment: .leading, spacing: 2) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(nsColor: Colors.surfaceSecondary))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(item.status == .paused
                              ? Color(nsColor: Colors.accentPrimary).opacity(0.7)
                              : Color(nsColor: Colors.accentPrimary))
                        .frame(width: max(0, geo.size.width * CGFloat(item.fractionComplete ?? 0)))
                }
            }
            .frame(height: 3)

            Text(item.status == .paused ? "Paused — \(progressString)" : progressString)
                .font(.system(size: 10))
                .foregroundStyle(Color(nsColor: Colors.foregroundSecondary))
        }
    }

    @ViewBuilder
    private var trailingAccessory: some View {
        HStack(spacing: 4) {
            controlButton(
                systemName: item.status == .paused ? "play.fill": "pause.fill",
                color: Color(nsColor: Colors.foregroundMuted),
                label: item.status == .paused ? "Resume": "Pause",
                action: item.status == .paused ? onResume: onPause
            )

            controlButton(
                systemName: "xmark",
                color: Color(
                    nsColor: Colors.foregroundMuted
                ),
                label: "Cancel",
                action: onCancel
            )
        }
    }

    private func controlButton(systemName: String, color: Color, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(color)
        }
        .buttonStyle(.plain)
        .help(label)
    }

    private var fileSizeString: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        if let total = item.totalBytes, total > 0 {
            return formatter.string(fromByteCount: total)
        }
        return formatter.string(fromByteCount: item.completedBytes)
    }

    private var progressString: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        let completed = formatter.string(fromByteCount: item.completedBytes)
        if let total = item.totalBytes, total > 0 {
            let totalStr = formatter.string(fromByteCount: total)
            return "\(completed) of \(totalStr)"
        }
        return completed
    }
}
