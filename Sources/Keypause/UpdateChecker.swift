import AppKit
import Foundation

struct ReleaseInfo {
    let version: String
    let pageURL: URL
    let downloadURL: URL?
    let notes: String
}

/// Looks for a newer release on GitHub. It only reads the public releases API and never installs anything:
/// the user decides whether to download. Nothing about the user is sent.
@MainActor
final class UpdateChecker {
    static let owner = "destucr", repo = "Keypause"

    enum Outcome { case upToDate(String), available(ReleaseInfo), failed(String) }

    /// Set when a newer release is known, so the menu can show a passive "Update available" item.
    var available: ReleaseInfo?

    /// The running version. `--update-test-version=0.9.0` overrides it, for testing the update flow.
    var currentVersion: String {
        if let arg = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--update-test-version=") }) {
            return String(arg.dropFirst("--update-test-version=".count))
        }
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    func check() async -> Outcome {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.owner)/\(Self.repo)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Keypause/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .failed("No response from GitHub.") }
            guard http.statusCode == 200 else { return .failed("GitHub answered with status \(http.statusCode).") }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String, Self.isVersion(tag),
                  let page = (json["html_url"] as? String).flatMap(URL.init(string:)), Self.isOurs(page)
            else { return .failed("Unexpected answer from GitHub.") }

            let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            guard Self.isNewer(latest, than: currentVersion) else { return .upToDate(currentVersion) }

            let assets = (json["assets"] as? [[String: Any]]) ?? []
            let dmg = assets.compactMap { $0["browser_download_url"] as? String }
                .compactMap(URL.init(string:)).first { $0.pathExtension == "dmg" && Self.isOurs($0) }
            return .available(ReleaseInfo(version: latest, pageURL: page, downloadURL: dmg, notes: Self.plainNotes((json["body"] as? String) ?? "")))
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// GitHub release notes are Markdown; show them as short plain bullets.
    static func plainNotes(_ markdown: String) -> String {
        let bullets = markdown.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("- ") || $0.hasPrefix("* ") }
            .map { "• " + $0.dropFirst(2).replacingOccurrences(of: "`", with: "").replacingOccurrences(of: "**", with: "") }
        return bullets.prefix(4).joined(separator: "\n")
    }

    /// Only ever offer links that point at this project's own GitHub releases.
    private static func isOurs(_ url: URL) -> Bool {
        url.scheme == "https" && url.host == "github.com" && url.path.hasPrefix("/\(owner)/\(repo)/")
    }
    private static func isVersion(_ s: String) -> Bool {
        s.range(of: #"^v?\d+(\.\d+){1,3}$"#, options: .regularExpression) != nil
    }
    static func isNewer(_ a: String, than b: String) -> Bool {
        func parts(_ s: String) -> [Int] { s.split(separator: ".").map { Int($0) ?? 0 } }
        let (x, y) = (parts(a), parts(b))
        for i in 0..<max(x.count, y.count) {
            let (p, q) = (i < x.count ? x[i] : 0, i < y.count ? y[i] : 0)
            if p != q { return p > q }
        }
        return false
    }

    /// Installed with Homebrew? Then the right way to update is `brew upgrade`.
    static var installedWithHomebrew: Bool {
        ["/opt/homebrew/Caskroom/keypause", "/usr/local/Caskroom/keypause"].contains { FileManager.default.fileExists(atPath: $0) }
    }
}
