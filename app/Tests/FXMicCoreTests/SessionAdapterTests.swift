import Foundation
import Testing
@testable import FXMicCore

@Suite struct SessionAdapterTests {
    private let claudeLog = """
    2026-10-22 11:29:21 [info] [CCD] LocalSessions.setFocusedSession: sessionId=null
    2026-10-22 11:29:21 [info] [CCD] LocalSessions.setFocusedSession: sessionId=local_b222644b-b880-474a-bade-18e67d9b5943
    2026-10-22 11:30:01 [info] [CCD] LocalSessions.setFocusedSession: sessionId=null
    2026-10-22 11:30:01 [info] [CCD] LocalSessions.setFocusedSession: sessionId=local_36f75384-0067-4ad5-8db4-80457269a4dd
    2026-10-22 11:30:05 [info] [git-worker] something else
    """

    private let codexLog = """
    2026-10-22T09:30:46.543Z info [x] thread_stream_view_activity_changed active=false conversationId=01a0332d-d141-7cf1-9ba5-b5792b631c05 rendererWindowFocused=true
    2026-10-22T09:30:46.548Z info [x] thread_stream_view_activity_changed active=true conversationId=01a10b0b-5a81-7c22-954e-5aeb9831ec34 rendererWindowFocused=true
    2026-10-22T09:30:50.040Z info [x] noise
    """

    @Test func claudeLastFocusedSession() throws {
        let found = try #require(SessionAdapter.claudeDesktop.lastEvent(in: claudeLog))
        #expect(found.event == .focus("local_36f75384-0067-4ad5-8db4-80457269a4dd"))
        #expect(found.timestamp != nil)
    }

    @Test func claudeTrailingNullMeansNoSession() throws {
        let found = try #require(SessionAdapter.claudeDesktop.lastEvent(in: claudeLog + "\n2026-10-22 11:31:00 [info] [CCD] LocalSessions.setFocusedSession: sessionId=null"))
        #expect(found.event == .blur)
    }

    @Test func codexLastEventIsTheNewThread() throws {
        let found = try #require(SessionAdapter.codexDesktop.lastEvent(in: codexLog))
        #expect(found.event == .focus("01a10b0b-5a81-7c22-954e-5aeb9831ec34"))
        let expected = try #require(ISO8601DateFormatter().date(from: "2026-10-22T09:30:46Z")).addingTimeInterval(0.548)
        #expect(abs(try #require(found.timestamp).timeIntervalSince(expected)) < 0.01)
    }

    @Test func codexLeavingThreadsIsABlur() throws {
        let log = codexLog.components(separatedBy: "\n").prefix(1).joined(separator: "\n")
        #expect(try #require(SessionAdapter.codexDesktop.lastEvent(in: log)).event == .blur)
    }

    @Test func noMatchOrBrokenPatternGivesNil() {
        #expect(SessionAdapter.claudeDesktop.lastEvent(in: "nothing here") == nil)
        let broken = SessionAdapter(bundleID: "x", logDirectory: "/tmp", focusPattern: "(", link: "x://{id}")
        #expect(broken.lastEvent(in: "(") == nil)
    }

    @Test func linksAreBuiltFromTheTemplate() {
        #expect(SessionAdapter.claudeDesktop.url(for: "local_b222644b-b880")?.absoluteString == "claude://code/continue?session=local_b222644b-b880")
        #expect(SessionAdapter.codexDesktop.url(for: "019f0376-0374-7772")?.absoluteString == "codex://threads/019f0376-0374-7772")
        #expect(SessionAdapter.codexDesktop.url(for: "../../etc") == nil)
        #expect(SessionAdapter.codexDesktop.url(for: "a b&c=d12345") == nil)
    }

    @Test func userAdapterWinsOverBuiltIn() {
        let mine = SessionAdapter(bundleID: "com.openai.codex", logDirectory: "/x", focusPattern: "(a)", link: "mine://{id}")
        #expect(SessionAdapter.adapter(for: "com.openai.codex", custom: [mine])?.link == "mine://{id}")
        #expect(SessionAdapter.adapter(for: "com.openai.codex", custom: [])?.name == "Codex")
        #expect(SessionAdapter.adapter(for: "com.example.app", custom: []) == nil)
    }

    @Test func customAdaptersLiveInConfig() throws {
        let json = #"{"sessionAdapters":[{"bundleID":"dev.zed.Zed","logDirectory":"~/Library/Logs/Zed","focusPattern":"thread (\\w+) focused","link":"zed://thread/{id}"}]}"#
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        #expect(config.sessionAdapters.map(\.bundleID) == ["dev.zed.Zed"])
        let back = try JSONDecoder().decode(AppConfig.self, from: JSONEncoder().encode(config))
        #expect(back.sessionAdapters == config.sessionAdapters)
        #expect(AppConfig().sessionAdapters.isEmpty)
    }
}

@Suite struct WebPageLinkTests {
    private let chat = "https://claude.ai/chat/da49058b-7b09-40c1-8607-742b78022f18"

    @Test func claudeChatAndProjectUrlsBecomeDeepLinks() {
        let claude = SessionAdapter.claudeDesktop
        #expect(claude.webLink(forURL: chat) == "claude://claude.ai/chat/da49058b-7b09-40c1-8607-742b78022f18")
        #expect(claude.webLink(forURL: chat + "?utm=x#top") == "claude://claude.ai/chat/da49058b-7b09-40c1-8607-742b78022f18")
        #expect(claude.webLink(forURL: "https://claude.ai/project/da49058b-7b09-40c1-8607-742b78022f18")
                == "claude://claude.ai/project/da49058b-7b09-40c1-8607-742b78022f18")
    }

    @Test func otherPagesAndOtherAppsGiveNoLink() {
        #expect(SessionAdapter.claudeDesktop.webLink(forURL: "https://claude.ai/recents") == nil)
        #expect(SessionAdapter.claudeDesktop.webLink(forURL: "https://evil.example/chat/da49058b-7b09-40c1-8607-742b78022f18") == nil)
        #expect(SessionAdapter.claudeDesktop.webLink(forURL: "https://claude.ai/chat/not-an-id") == nil)
        #expect(SessionAdapter.codexDesktop.webLink(forURL: chat) == nil)
    }

    @Test func onlyLinksThatLookLikeTheTemplateAreOpened() {
        let claude = SessionAdapter.claudeDesktop
        #expect(claude.accepts(webLink: "claude://claude.ai/chat/da49058b-7b09-40c1-8607-742b78022f18"))
        #expect(!claude.accepts(webLink: "https://claude.ai/chat/x"))
        #expect(!claude.accepts(webLink: "file:///etc/passwd"))
        #expect(!SessionAdapter.codexDesktop.accepts(webLink: "claude://claude.ai/chat/x"))
    }
}

@Suite struct ChannelLinkTests {
    private let id = "com.anthropic.claudefordesktop"
    private let chatA = "claude://claude.ai/chat/da49058b-7b09-40c1-8607-742b78022f18"
    private let chatB = "claude://claude.ai/chat/aaaaaaaa-7b09-40c1-8607-742b78022f18"

    @Test func aChatChannelMatchesOnlyThatChat() {
        let channel = Channel(name: "Claude · chat", bundleID: id, link: chatA)
        #expect(channel.matches(window: Channel(name: "w", bundleID: id, link: chatA)))
        #expect(!channel.matches(window: Channel(name: "w", bundleID: id, link: chatB)))
        #expect(!channel.matches(window: Channel(name: "w", bundleID: id, session: "local_a")))
        #expect(channel.specificity == 3)
    }

    @Test func aChatBeatsTheWholeAppAndASessionIsADifferentChannel() {
        var config = AppConfig()
        config.channels = [Channel(name: "Claude", bundleID: id),
                           Channel(name: "chat", bundleID: id, link: chatA),
                           Channel(name: "session", bundleID: id, session: "local_a")]
        let engine = ProfileEngine(config: config)
        #expect(engine.channelIndex(forWindow: Channel(name: "w", bundleID: id, link: chatA)) == 1)
        #expect(engine.channelIndex(forWindow: Channel(name: "w", bundleID: id, session: "local_a")) == 2)
        #expect(engine.channelIndex(forWindow: Channel(name: "w", bundleID: id, link: chatB)) == 0)
    }

    @Test func bindingAChatDoesNotReplaceASessionAndTwoChatsAreTwoChannels() {
        var engine = ProfileEngine(config: AppConfig())
        engine.bind(Channel(name: "s", bundleID: id, session: "local_a"))
        #expect(engine.bind(Channel(name: "a", bundleID: id, link: chatA)) == .init(index: 1, kind: .added))
        #expect(engine.bind(Channel(name: "b", bundleID: id, link: chatB)) == .init(index: 2, kind: .added))
        #expect(engine.bind(Channel(name: "a again", bundleID: id, link: chatA)) == .init(index: 1, kind: .updated))
    }

    @Test func theLinkSurvivesAConfigRoundTrip() throws {
        var config = AppConfig()
        config.channels = [Channel(name: "chat", bundleID: id, link: chatA)]
        let back = try JSONDecoder().decode(AppConfig.self, from: JSONEncoder().encode(config))
        #expect(back.channels.first?.link == chatA)
    }
}
