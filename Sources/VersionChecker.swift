import Foundation

/// Polls the GitHub Releases API once a day for the latest version.
/// Stores `latestKnownVersion` in Preferences so the menu can highlight
/// when a newer version is available. No keys, no signing, no service.
final class VersionChecker {

    static let shared = VersionChecker()
    static let releasesURL = "https://github.com/turkbil/claude-usage-widget/releases"

    private let apiURL = URL(string: "https://api.github.com/repos/turkbil/claude-usage-widget/releases/latest")!
    private let oneDay: TimeInterval = 24 * 3600

    private init() {}

    /// Run on app launch and any time refresh fires.
    func checkIfDue() {
        var prefs = PrefsStore.shared.prefs
        guard prefs.versionCheckEnabled else { return }
        let now = Date().timeIntervalSince1970
        guard now - prefs.lastVersionCheckEpoch > oneDay else { return }
        prefs.lastVersionCheckEpoch = now
        PrefsStore.shared.update { $0.lastVersionCheckEpoch = now }
        fetchLatest()
    }

    /// Bundle version stripped of any `v` prefix.
    var currentVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.0.0"
    }

    /// True if `latestKnownVersion` represents a strictly newer release.
    var updateAvailable: Bool {
        let latest = PrefsStore.shared.prefs.latestKnownVersion.trimmingCharacters(in: CharacterSet(charactersIn: "v "))
        guard !latest.isEmpty else { return false }
        return compareSemver(latest, vs: currentVersion) == .orderedDescending
    }

    // MARK: - private

    private func fetchLatest() {
        var req = URLRequest(url: apiURL)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else { return }
            let cleaned = tag.trimmingCharacters(in: CharacterSet(charactersIn: "v "))
            PrefsStore.shared.update { $0.latestKnownVersion = cleaned }
        }.resume()
    }

    /// Naive dotted-int comparison (e.g. "1.2.0" vs "1.10.3").
    private func compareSemver(_ a: String, vs b: String) -> ComparisonResult {
        let ax = a.split(separator: ".").compactMap { Int($0) }
        let bx = b.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(ax.count, bx.count) {
            let av = i < ax.count ? ax[i] : 0
            let bv = i < bx.count ? bx[i] : 0
            if av < bv { return .orderedAscending }
            if av > bv { return .orderedDescending }
        }
        return .orderedSame
    }
}
