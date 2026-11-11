import Foundation
import SwiftUI

@MainActor @Observable final class GitHubCalendarModel {
    var levels: [String: Int] = [:]
    var loading = false
    var error: String?

    func load(username: String) async {
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        levels = [:]
        guard !name.isEmpty else { levels = [:]; error = nil; return }
        guard name.range(of: "^[A-Za-z0-9-]{1,39}$", options: .regularExpression) != nil else {
            error = "Enter a valid GitHub username"
            return
        }
        loading = true
        error = nil
        defer { loading = false }

        var parts = URLComponents(string: "https://github.com/users/\(name)/contributions")!
        parts.queryItems = [URLQueryItem(name: "to", value: ISO8601DateFormatter.githubDay.string(from: Date()))]
        guard let url = parts.url else { error = "Could not create GitHub request"; return }
        do {
            var request = URLRequest(url: url)
            request.setValue("text/html", forHTTPHeaderField: "Accept")
            request.setValue("TopNotch/1.0", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                error = "GitHub could not load that profile"
                return
            }
            let html = String(decoding: data, as: UTF8.self)
            let parsed = Self.parseLevels(html)
            guard !parsed.isEmpty else { error = "No public contribution calendar found"; return }
            levels = parsed
        } catch {
            self.error = "Could not reach GitHub. Check your connection and try again."
        }
    }

    private static func parseLevels(_ html: String) -> [String: Int] {
        let tagPattern = #"<[^>]*data-date="(\d{4}-\d{2}-\d{2})"[^>]*>"#
        guard let tags = try? NSRegularExpression(pattern: tagPattern) else { return [:] }
        let source = html as NSString
        let attr = try? NSRegularExpression(pattern: #"data-level="(\d)""#)
        var result: [String: Int] = [:]
        for match in tags.matches(in: html, range: NSRange(location: 0, length: source.length)) {
            guard match.numberOfRanges > 1 else { continue }
            let date = source.substring(with: match.range(at: 1))
            let tag = source.substring(with: match.range)
            let tagSource = tag as NSString
            let levelMatch = attr?.firstMatch(in: tag, range: NSRange(location: 0, length: tagSource.length))
            let level = levelMatch.flatMap { $0.numberOfRanges > 1 ? Int(tagSource.substring(with: $0.range(at: 1))) : nil } ?? 0
            result[date] = level
        }
        return result
    }
}

private extension ISO8601DateFormatter {
    static let githubDay: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()
}

struct GitHubCalendarPane: View {
    @AppStorage("githubUsername") private var savedUsername = ""
    @State private var username = ""
    @State private var model = GitHubCalendarModel()

    private let cell = 8.0
    private let gap = 2.0
    private let dayNames = ["M", "W", "F"]

    private var weeks: [[Date]] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 1
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = calendar.startOfDay(for: Date())
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: today)!.start
        let start = calendar.date(byAdding: .weekOfYear, value: -51, to: thisWeek)!
        return (0..<52).map { week in
            (0..<7).compactMap { day in calendar.date(byAdding: .day, value: week * 7 + day, to: start) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "chevron.left.forwardslash.chevron.right").foregroundStyle(Color.neon)
                Text("GitHub contributions").font(sans(14, .semibold))
                Spacer()
                TextField("GitHub username", text: $username)
                    .textFieldStyle(.plain).font(mono(11)).frame(width: 130)
                    .padding(.horizontal, 8).frame(height: 25)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                    .onSubmit { savedUsername = username }
                Button {
                    if username == savedUsername { Task { await model.load(username: username) } }
                    else { savedUsername = username }
                } label: {
                    Image(systemName: model.loading ? "arrow.clockwise" : "arrow.clockwise")
                        .foregroundStyle(Color.neon).rotationEffect(.degrees(model.loading ? 360 : 0))
                }
                .disabled(model.loading || username.isEmpty)
                .help("Refresh GitHub contributions")
            }

            if savedUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Empty(icon: "chevron.left.forwardslash.chevron.right", title: "Add your GitHub username", sub: "PUBLIC CONTRIBUTIONS · NO SIGN IN")
            } else if let error = model.error {
                Empty(icon: "exclamationmark.triangle", title: error, sub: "CHECK THE USERNAME AND TRY AGAIN")
            } else {
                contributionGrid
            }
        }
        .padding(12)
        .card(.neon)
        .task(id: savedUsername) {
            username = savedUsername
            await model.load(username: savedUsername)
        }
    }

    private var contributionGrid: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: gap) {
                Color.clear.frame(width: 18)
                ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                    let date = week[0]
                    let firstInMonth = Calendar(identifier: .gregorian).component(.day, from: date) <= 7
                    Text(firstInMonth ? date.formatted(.dateTime.month(.abbreviated)) : "")
                        .font(mono(7, .medium)).foregroundStyle(Color.fg3).frame(width: cell, alignment: .leading)
                }
            }
            HStack(alignment: .top, spacing: gap) {
                VStack(spacing: gap) {
                    ForEach(Array(0..<7), id: \.self) { day in
                        Text(["", "M", "", "W", "", "F", ""][day])
                            .font(mono(7)).foregroundStyle(Color.fg3).frame(width: 16, height: cell)
                    }
                }
                HStack(spacing: gap) {
                    ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                        VStack(spacing: gap) {
                            ForEach(week, id: \.self) { date in
                                let key = ISO8601DateFormatter.githubDay.string(from: date)
                                let level = model.levels[key] ?? 0
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(levelColor(level))
                                    .frame(width: cell, height: cell)
                                    .help("\(level == 0 ? "No" : "Some") public contributions · \(key)")
                            }
                        }
                    }
                }
            }
            HStack(spacing: 5) {
                Spacer()
                Caps(text: "Less", color: .fg3)
                ForEach(0..<5, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 2).fill(levelColor(level)).frame(width: cell, height: cell)
                }
                Caps(text: "More", color: .fg3)
                Text("· last year · @\(savedUsername)").font(mono(8)).foregroundStyle(Color.fg3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func levelColor(_ level: Int) -> Color {
        let colors: [Color] = [.white.opacity(0.07), .neon.opacity(0.28), .neon.opacity(0.48), .neon.opacity(0.72), .neon]
        return colors[min(max(level, 0), colors.count - 1)]
    }
}
