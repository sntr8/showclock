import AppKit

// Checks GitHub Releases for a newer tagged version than the one currently
// running. No Sparkle/appcast infrastructure — just the plain "latest
// release" API endpoint, since that's all a single-repo open-source project
// needs.
enum UpdateChecker {
    private static let releasesAPIURL = URL(string: "https://api.github.com/repos/sntr8/showclock/releases/latest")!
    private static let releasesPageURL = URL(string: "https://github.com/sntr8/showclock/releases")!

    // interactive: true shows "you're up to date" / network-error alerts too
    // (for the manual menu item); false stays silent unless there's actually
    // a newer version to report (for the automatic on-launch check — a
    // silent failure or "nothing new" shouldn't interrupt anyone).
    static func check(interactive: Bool) {
        // Bundle.main has no CFBundleShortVersionString at all when running
        // unbundled (swift run/swift build straight to a binary, as opposed
        // to the .app bundle Packaging/build-app.sh produces) — nothing
        // sensible to compare against, so just skip rather than guess.
        guard let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
            if interactive {
                showAlert(title: "Can't Check for Updates", body: "This build has no version number to compare (not a packaged .app).")
            }
            return
        }

        var request = URLRequest(url: releasesAPIURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("ShowClock-UpdateChecker", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { data, _, error in
            DispatchQueue.main.async {
                guard let data,
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tagName = obj["tag_name"] as? String else {
                    if interactive {
                        showAlert(title: "Can't Check for Updates", body: "Couldn't reach GitHub to check for a newer release. Try again later.")
                    }
                    return
                }
                let latestVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName

                if isNewer(latestVersion, than: currentVersion) {
                    let alert = NSAlert()
                    alert.messageText = "A New Version Is Available"
                    alert.informativeText = "ShowClock \(latestVersion) is available — you have \(currentVersion)."
                    alert.addButton(withTitle: "View Release")
                    alert.addButton(withTitle: "Later")
                    if alert.runModal() == .alertFirstButtonReturn {
                        NSWorkspace.shared.open(releasesPageURL)
                    }
                } else if interactive {
                    showAlert(title: "You're Up to Date", body: "ShowClock \(currentVersion) is the latest version.")
                }
            }
        }.resume()
    }

    private static func showAlert(title: String, body: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = body
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // Numeric component-wise comparison (1.2.10 > 1.2.9, unlike a plain
    // string compare). A component that fails to parse as an integer (e.g. a
    // local "-test" suffix from build-app.sh's dev usage) is dropped rather
    // than failing the whole comparison, so a locally-built dev version
    // doesn't crash this — it just compares on however many leading numeric
    // components it has.
    static func isNewer(_ remote: String, than local: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            s.split(separator: ".").compactMap { Int($0) }
        }
        let r = parts(remote)
        let l = parts(local)
        guard !r.isEmpty, !l.isEmpty else { return false }
        for i in 0..<max(r.count, l.count) {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv != lv { return rv > lv }
        }
        return false
    }
}
