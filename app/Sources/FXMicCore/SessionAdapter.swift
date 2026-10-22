import Foundation

/// How to find out which session an agent app shows and how to open one again (One-Pager 004
/// §4.3). Agent apps (Claude, Codex, and the ones to come) keep several sessions in one window, so
/// the window cannot tell them apart. An adapter describes two things, with no code per app:
/// the log lines that say which session got the focus, and the deep link that opens a session.
/// Built-in adapters cover Claude and Codex desktop; more can be added in `config.json` under
/// `sessionAdapters` and win over the built-in one for the same app.
public struct SessionAdapter: Codable, Equatable, Sendable {
    public var bundleID: String
    /// Name of the app when macOS reports a misleading one (Codex shows up as "ChatGPT").
    public var name: String?
    /// A log file, or a folder searched recursively for `.log` files. `~` is expanded.
    public var logDirectory: String
    /// Regex for the line that says a session got the focus. Group 1 is the session id.
    public var focusPattern: String
    /// Regex for the line that says no session is shown any more (optional).
    public var blurPattern: String?
    /// Deep link that opens a session; `{id}` is replaced with the session id.
    public var link: String

    public init(bundleID: String, name: String? = nil, logDirectory: String, focusPattern: String,
                blurPattern: String? = nil, link: String) {
        self.bundleID = bundleID
        self.name = name
        self.logDirectory = logDirectory
        self.focusPattern = focusPattern
        self.blurPattern = blurPattern
        self.link = link
    }

    // MARK: Built-in adapters

    public static let claudeDesktop = SessionAdapter(
        bundleID: "com.anthropic.claudefordesktop",
        logDirectory: "~/Library/Logs/Claude/main.log",
        focusPattern: "setFocusedSession: sessionId=(local_[A-Za-z0-9-]+)",
        blurPattern: "setFocusedSession: sessionId=null",
        link: "claude://code/continue?session={id}")

    public static let codexDesktop = SessionAdapter(
        bundleID: "com.openai.codex",
        name: "Codex",
        logDirectory: "~/Library/Logs/com.openai.codex",
        focusPattern: "thread_stream_view_activity_changed active=true conversationId=([0-9a-f-]{20,})",
        blurPattern: "thread_stream_view_activity_changed active=false conversationId=[0-9a-f-]{20,}",
        link: "codex://threads/{id}")

    public static let builtIn: [SessionAdapter] = [claudeDesktop, codexDesktop]

    /// The adapter for an app: the user's own first, then the built-in one.
    public static func adapter(for bundleID: String, custom: [SessionAdapter]) -> SessionAdapter? {
        custom.first { $0.bundleID == bundleID } ?? builtIn.first { $0.bundleID == bundleID }
    }

    // MARK: Reading a log

    public enum Event: Equatable, Sendable {
        case focus(String)
        case blur
    }

    public struct Found: Equatable, Sendable {
        public let event: Event
        /// Time written at the start of the line, when it can be read.
        public let timestamp: Date?
    }

    /// The last focus or blur line in a log text. "Last" because only the newest one counts: a
    /// switch usually logs the old session leaving and then the new one arriving.
    public func lastEvent(in text: String) -> Found? {
        let full = NSRange(location: 0, length: (text as NSString).length)
        func last(_ pattern: String) -> NSTextCheckingResult? {
            (try? NSRegularExpression(pattern: pattern))?.matches(in: text, range: full).last
        }
        let focus = last(focusPattern)
        let blur = blurPattern.flatMap(last)
        let ns = text as NSString
        let pick: (match: NSTextCheckingResult, event: Event)
        switch (focus, blur) {
        case (nil, nil): return nil
        case (let f?, nil): pick = (f, .focus(Self.id(in: f, of: ns)))
        case (nil, let b?): pick = (b, .blur)
        case (let f?, let b?):
            pick = f.range.location > b.range.location ? (f, .focus(Self.id(in: f, of: ns))) : (b, .blur)
        }
        if case .focus(let id) = pick.event, id.isEmpty { return nil }
        return Found(event: pick.event, timestamp: Self.timestamp(ofLineAt: pick.match.range.location, in: ns))
    }

    private static func id(in match: NSTextCheckingResult, of text: NSString) -> String {
        match.numberOfRanges > 1 && match.range(at: 1).location != NSNotFound ? text.substring(with: match.range(at: 1)) : ""
    }

    /// Reads `2026-10-22T12:09:42.241Z` (UTC) or `2026-10-22 11:30:04` (local time) at the start of the line.
    static func timestamp(ofLineAt location: Int, in text: NSString) -> Date? {
        let before = text.range(of: "\n", options: .backwards, range: NSRange(location: 0, length: location))
        let start = before.location == NSNotFound ? 0 : before.location + 1
        let line = text.substring(with: NSRange(location: start, length: min(40, text.length - start)))
        if let end = line.firstIndex(of: " "), line.contains("T"), line[..<end].hasSuffix("Z") {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: String(line[..<end])) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: String(line[..<end]))
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: String(line.prefix(19)))
    }

    // MARK: Deep link

    /// The link that opens a session; nil when the id is not a plain identifier.
    public func url(for session: String) -> URL? {
        guard session.range(of: "^[A-Za-z0-9_-]{8,80}$", options: .regularExpression) != nil else { return nil }
        return URL(string: link.replacingOccurrences(of: "{id}", with: session))
    }
}
