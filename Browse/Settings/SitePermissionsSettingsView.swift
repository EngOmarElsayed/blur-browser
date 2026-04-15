import SwiftUI

struct SitePermissionsSettingsView: View {
    @State private var permissionStore = SitePermissionStore.shared
    @State private var showClearPermissionsConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Site Permissions")
                    .font(.custom(Typography.fontFamily, size: 14).weight(.semibold))
                    .foregroundStyle(SettingsColors.fgPrimary)
                Spacer()
                if !permissionStore.allSites.isEmpty {
                    SettingsSecondaryButton("Remove All") {
                        showClearPermissionsConfirm = true
                    }
                    .confirmationDialog(
                        "Remove all saved site permissions?",
                        isPresented: $showClearPermissionsConfirm
                    ) {
                        Button("Remove All", role: .destructive) {
                            permissionStore.removeAll()
                        }
                    }
                }
            }

            if permissionStore.allSites.isEmpty {
                emptyState
            } else {
                permissionsTable
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(SettingsColors.fgSecondary)
            Text("No Saved Permissions")
                .font(.custom(Typography.fontFamily, size: 14).weight(.semibold))
                .foregroundStyle(SettingsColors.fgPrimary)
            Text("When websites request access to your camera, microphone, or location, they'll appear here.")
                .font(.custom(Typography.fontFamily, size: 12))
                .foregroundStyle(SettingsColors.fgSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Which columns are needed

    /// Check across all sites which permission types have been requested
    private var showCamera: Bool {
        permissionStore.allSites.contains { $0.permissions.camera != nil }
    }
    private var showMicrophone: Bool {
        permissionStore.allSites.contains { $0.permissions.microphone != nil }
    }
    private var showLocation: Bool {
        permissionStore.allSites.contains { $0.permissions.location != nil }
    }

    // MARK: - Permissions Table

    private var permissionsTable: some View {
        SettingsTable {
            // Header
            SettingsTableHeader {
                SettingsTableHeaderCell("Site", flex: 1)

                HStack(alignment: .center, spacing: 12) {
                    if showCamera {
                        SettingsTableHeaderCell("Camera", flex: 2, fullwidth: false)
                    }
                    if showMicrophone {
                        SettingsTableHeaderCell("Microphone", flex: 3, fullwidth: false)
                    }
                    if showLocation {
                        SettingsTableHeaderCell("Location", flex: 4, fullwidth: false)
                    }
                }
                // Delete column header (empty)
                Color.clear.frame(width: 50)
            }

            // Rows
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(permissionStore.allSites.map {
                        SitePermissionRow(host: $0.host, permissions: $0.permissions)
                    }) { row in
                        SettingsTableRow {
                            // Site name
                            Text(row.host)
                                .font(.custom(Typography.fontFamily, size: 12))
                                .foregroundStyle(SettingsColors.fgPrimary)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)

                            HStack(alignment: .center, spacing: 8) {
                                // Camera picker — only if this column is shown
                                if showCamera {
                                    if row.permissions.camera != nil {
                                        permissionPicker(for: row.host, type: .camera, current: row.permissions.camera ?? .ask)
                                    } else {
                                        Text("—")
                                            .font(.custom(Typography.fontFamily, size: 12))
                                            .foregroundStyle(SettingsColors.fgSecondary.opacity(0.5))
                                            .frame(width: 80)
                                    }
                                }

                                // Microphone picker
                                if showMicrophone {
                                    if row.permissions.microphone != nil {
                                        permissionPicker(for: row.host, type: .microphone, current: row.permissions.microphone ?? .ask)
                                    } else {
                                        Text("—")
                                            .font(.custom(Typography.fontFamily, size: 12))
                                            .foregroundStyle(SettingsColors.fgSecondary.opacity(0.5))
                                            .frame(width: 80)
                                    }
                                }

                                // Location picker
                                if showLocation {
                                    if row.permissions.location != nil {
                                        permissionPicker(for: row.host, type: .location, current: row.permissions.location ?? .ask)
                                    } else {
                                        Text("—")
                                            .font(.custom(Typography.fontFamily, size: 12))
                                            .foregroundStyle(SettingsColors.fgSecondary.opacity(0.5))
                                            .frame(width: 80)
                                    }
                                }
                            }

                            // Delete button
                            Button {
                                permissionStore.removeSite(row.host)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 12))
                                    .foregroundStyle(SettingsColors.fgSecondary)
                            }
                            .buttonStyle(.plain)
                            .frame(width: 50)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Permission Picker

    private func permissionPicker(for host: String, type: SitePermissionType, current: PermissionPolicy) -> some View {
        Picker("", selection: Binding(
            get: { permissionStore.effectivePolicy(for: host, type: type) },
            set: { permissionStore.setPolicy($0, for: host, type: type) }
        )) {
            ForEach(PermissionPolicy.allCases) { policy in
                Text(policy.displayName).tag(policy)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .font(.custom(Typography.fontFamily, size: 12))
        .tint(colorForPolicy(current))
    }

    private func colorForPolicy(_ policy: PermissionPolicy) -> Color {
        switch policy {
        case .allow: return SettingsColors.allowGreen
        case .deny:  return SettingsColors.denyRed
        case .ask:   return SettingsColors.fgSecondary
        }
    }
}

// MARK: - Site Permission Row

struct SitePermissionRow: Identifiable {
    let host: String
    let permissions: SitePermissions
    var id: String { host }
}
