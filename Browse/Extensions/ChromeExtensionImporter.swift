import Foundation

/// Prepares unpacked Chrome extensions for WebKit, and finds the ones already
/// installed in Chromium browsers on this Mac.
///
/// Unpacked folders are copied into
/// `~/Library/Application Support/Blur-Browser/Extensions/<install id>/`, and
/// `blur-chrome-compat.js` is put in front of the background script. The shim
/// stands in for Chrome APIs WebKit lacks (`notifications`, `downloads`,
/// `idle`, `management`, `privacy`, `storage.managed`, a few events). Without
/// it, extensions such as 1Password die on startup. The copy keeps the
/// manifest's `key`, so the Chrome extension ID, which native messaging hosts
/// check, stays the same.
enum ChromeExtensionImporter {
    static let compatFileName = "blur-chrome-compat.js"

    static var managedRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/\(AppConstants.appName)/Extensions", isDirectory: true)
    }

    static func managedCopyURL(forInstallID id: String) -> URL {
        managedRoot.appendingPathComponent(id, isDirectory: true)
    }

    static func isManagedCopy(_ url: URL) -> Bool {
        url.standardizedFileURL.path.hasPrefix(managedRoot.standardizedFileURL.path + "/")
    }

    /// Copy `folder` into the managed location and apply the compat shim.
    /// Returns the folder WebKit should load.
    static func prepareManagedCopy(of folder: URL, installID: String) throws -> URL {
        let fileManager = FileManager.default
        let destination = managedCopyURL(forInstallID: installID)
        try fileManager.createDirectory(at: managedRoot, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: folder, to: destination)
        // Chrome Web Store signature data; meaningless here.
        try? fileManager.removeItem(at: destination.appendingPathComponent("_metadata"))
        try applyCompatShim(in: destination)
        return destination
    }

    static func removeManagedCopy(at url: URL) {
        guard isManagedCopy(url) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Put the shim in front of the extension's background code.
    /// - MV3 `background.service_worker`: write `<dir>/blur-<name>` containing
    ///   the shim followed by the original worker, and point the manifest at it.
    ///   A sibling file keeps relative `import`s and `importScripts` working.
    ///   (A separate shim module isn't enough: 1Password's worker failed that way.)
    /// - MV2 `background.scripts`: prepend the shim file.
    static func applyCompatShim(in folder: URL) throws {
        guard let shimURL = Bundle.main.url(forResource: "blur-chrome-compat", withExtension: "js") else { return }
        let shim = try String(contentsOf: shimURL, encoding: .utf8)
        let manifestURL = folder.appendingPathComponent("manifest.json")
        let data = try Data(contentsOf: manifestURL)
        guard var manifest = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var background = manifest["background"] as? [String: Any] else { return }

        if let worker = background["service_worker"] as? String {
            let workerURL = folder.appendingPathComponent(worker)
            let original = try String(contentsOf: workerURL, encoding: .utf8)
            let combinedName = "blur-" + workerURL.lastPathComponent
            let combinedURL = workerURL.deletingLastPathComponent().appendingPathComponent(combinedName)
            try (shim + "\n" + original).write(to: combinedURL, atomically: true, encoding: .utf8)
            background["service_worker"] = (worker as NSString).deletingLastPathComponent.isEmpty
                ? combinedName
                : ((worker as NSString).deletingLastPathComponent as NSString).appendingPathComponent(combinedName)
        } else if var scripts = background["scripts"] as? [String] {
            try shim.write(to: folder.appendingPathComponent(compatFileName), atomically: true, encoding: .utf8)
            scripts.removeAll { $0 == compatFileName }
            background["scripts"] = [compatFileName] + scripts
        } else {
            return
        }
        manifest["background"] = background
        let output = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .withoutEscapingSlashes])
        try output.write(to: manifestURL, options: .atomic)
    }

    // MARK: - Chromium browsers on this Mac

    struct Found: Identifiable {
        let id: String          // Chrome extension ID
        let name: String
        let version: String
        let browser: String     // e.g. "Arc", "Google/Chrome"
        let folder: URL
    }

    /// Extensions installed in Chromium-based browsers' profiles under
    /// ~/Library/Application Support (Chrome, Arc, Brave, Edge, Vivaldi, …).
    /// Keeps the newest version of each extension ID.
    static func findInstalledChromiumExtensions() -> [Found] {
        let fileManager = FileManager.default
        let appSupport = fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        var newest: [String: Found] = [:]

        // Profiles live at <app>/<profile>/Extensions, <app>/User Data/<profile>/Extensions
        // (Arc) or <vendor>/<app>/<profile>/Extensions (Google/Chrome, BraveSoftware/…).
        var extensionDirs: [(browser: String, dir: URL)] = []
        func scan(_ url: URL, label: String, depth: Int) {
            guard depth <= 3,
                  let children = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return }
            for child in children where (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                if child.lastPathComponent == "Extensions", depth >= 1 {
                    extensionDirs.append((label, child))
                } else if depth < 3 {
                    scan(child, label: label, depth: depth + 1)
                }
            }
        }
        let skip: Set<String> = [AppConstants.appName, "Claude", "Code", "Slack", "discord"]
        for app in (try? fileManager.contentsOfDirectory(at: appSupport, includingPropertiesForKeys: nil)) ?? []
        where !skip.contains(app.lastPathComponent) {
            scan(app, label: app.lastPathComponent, depth: 0)
        }

        let idPattern = /^[a-p]{32}$/
        for (browser, dir) in extensionDirs {
            for extensionDir in (try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            where extensionDir.lastPathComponent.wholeMatch(of: idPattern) != nil {
                for versionDir in (try? fileManager.contentsOfDirectory(at: extensionDir, includingPropertiesForKeys: nil)) ?? [] {
                    let manifestURL = versionDir.appendingPathComponent("manifest.json")
                    guard let data = try? Data(contentsOf: manifestURL),
                          let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          manifest["key"] != nil else { continue }
                    let version = manifest["version"] as? String ?? "0"
                    let found = Found(id: extensionDir.lastPathComponent,
                                      name: localizedName(manifest, in: versionDir),
                                      version: version, browser: browser, folder: versionDir)
                    if let existing = newest[found.id],
                       existing.version.compare(version, options: .numeric) != .orderedAscending { continue }
                    newest[found.id] = found
                }
            }
        }
        return newest.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Resolve `__MSG_name__` against the default locale's messages.json.
    private static func localizedName(_ manifest: [String: Any], in folder: URL) -> String {
        let raw = manifest["name"] as? String ?? folder.deletingLastPathComponent().lastPathComponent
        guard raw.hasPrefix("__MSG_"), raw.hasSuffix("__") else { return raw }
        let key = String(raw.dropFirst(6).dropLast(2))
        let locale = manifest["default_locale"] as? String ?? "en"
        let messagesURL = folder.appendingPathComponent("_locales/\(locale)/messages.json")
        guard let data = try? Data(contentsOf: messagesURL),
              let messages = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return raw }
        let entry = messages.first { $0.key.caseInsensitiveCompare(key) == .orderedSame }?.value as? [String: Any]
        return entry?["message"] as? String ?? raw
    }
}
