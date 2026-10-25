import Foundation
import Testing
@testable import FXMicCore

@Suite struct ChannelTests {
    private let claude = Channel(name: "Claude", bundleID: "com.anthropic.claudefordesktop", title: "Claude")
    private let notes = Channel(name: "Code · TODO.md", bundleID: "com.microsoft.VSCode",
                                document: "file:///tmp/TODO.md", title: "TODO.md")
    private let word = Channel(name: "Word", bundleID: "com.microsoft.Word", title: "Doc1")

    private func engine(with channels: [Channel] = []) -> ProfileEngine {
        var config = AppConfig()
        config.channels = channels
        return ProfileEngine(config: config)
    }

    @Test func startsFreeWithNoRedLed() {
        let engine = engine()
        #expect(engine.channelPosition == nil)
        #expect(engine.channel == nil)
        #expect(engine.idleLEDs == 0)
    }

    @Test func bindingAddsChannelsInOrder() {
        var engine = engine()
        #expect(engine.bind(claude) == .init(index: 0, kind: .added))
        #expect(engine.bind(notes) == .init(index: 1, kind: .added))
        #expect(engine.config.channels == [claude, notes])
        #expect(engine.channelPosition == 1)
        #expect(engine.idleLEDs == 0b0000_0010)
    }

    @Test func nextAndPreviousWrapAndStartFromFree() {
        var engine = engine(with: [claude, notes, word])
        engine.nextChannel()
        #expect(engine.channelPosition == 0)
        engine.nextChannel(); engine.nextChannel(); engine.nextChannel()
        #expect(engine.channelPosition == 0)
        engine.previousChannel()
        #expect(engine.channelPosition == 2)
        engine.setFocus(nil)
        engine.previousChannel()
        #expect(engine.channelPosition == 2)
    }

    @Test func noChannelsMeansAlwaysFree() {
        var engine = engine()
        engine.nextChannel()
        engine.previousChannel()
        #expect(engine.channelPosition == nil)
    }

    @Test func fullListReplacesTheChannelYouAreOn() {
        var engine = engine(with: [claude, notes, word, Channel(name: "Mail", bundleID: "mail")])
        engine.setFocus(1)
        let replacement = Channel(name: "Slack", bundleID: "slack", title: "x")
        #expect(engine.bind(replacement) == .init(index: 1, kind: .replaced))
        #expect(engine.config.channels.map(\.name) == ["Claude", "Slack", "Word", "Mail"])
    }

    @Test func fullListFromFreeReplacesTheLastOne() {
        var engine = engine(with: [claude, notes, word, Channel(name: "Mail", bundleID: "mail")])
        engine.setFocus(nil)
        let replacement = Channel(name: "Slack", bundleID: "slack", title: "x")
        #expect(engine.bind(replacement) == .init(index: 3, kind: .replaced))
        #expect(engine.config.channels.count == 4)
    }

    @Test func neverMoreThanFourChannels() {
        var engine = engine()
        for i in 0..<6 { engine.bind(Channel(name: "A\(i)", bundleID: "app.\(i)", title: "t")) }
        #expect(engine.config.channels.count == 4)
    }

    @Test func bindingTheSameWindowUpdatesItsChannel() {
        var engine = engine(with: [claude, notes])
        var renamed = notes
        renamed.title = "TODO.md — edited"
        #expect(engine.bind(renamed) == .init(index: 1, kind: .updated))
        #expect(engine.config.channels.count == 2)
        #expect(engine.channelPosition == 1)
    }

    @Test func unbindRemovesTheCurrentChannelAndFrees() {
        var engine = engine(with: [claude, notes])
        engine.setFocus(0)
        let removed = engine.unbindChannel()
        #expect(removed)
        #expect(engine.config.channels == [notes])
        #expect(engine.channelPosition == nil)
        let removedAgain = engine.unbindChannel()
        #expect(!removedAgain)
    }

    @Test func clearAllEmptiesEverythingAndCanBeUndoneOnce() {
        var engine = engine(with: [claude, notes, word])
        engine.setFocus(1)
        let removed = engine.clearChannels()
        #expect(removed == [claude, notes, word])
        #expect(engine.config.channels.isEmpty)
        #expect(engine.channelPosition == nil)
        engine.restoreChannels(removed)
        #expect(engine.config.channels == [claude, notes, word])
        // Not when something was bound in the meantime.
        var other = self.engine()
        other.bind(word)
        other.restoreChannels([claude, notes])
        #expect(other.config.channels == [word])
    }

    @Test func reloadDropsAPositionThatNoLongerExists() {
        var engine = engine(with: [claude, notes])
        engine.setFocus(1)
        engine.reload(AppConfig())
        #expect(engine.channelPosition == nil)
        engine.setFocus(5)
        #expect(engine.channelPosition == nil)
    }

    @Test func channelsPersistInConfig() throws {
        var config = AppConfig()
        config.channels = [claude, notes]
        let data = try JSONEncoder().encode(config)
        let back = try JSONDecoder().decode(AppConfig.self, from: data)
        #expect(back.channels == [claude, notes])
        let json = #"{"channels":[{"name":"A","bundleID":"a"},{"name":"B","bundleID":"b"},{"name":"C","bundleID":"c"},{"name":"D","bundleID":"d"},{"name":"E","bundleID":"e"}]}"#
        #expect(try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8)).channels.count == 4)
        let broken = #"{"channels":[{"nope":1}]}"#
        #expect(try JSONDecoder().decode(AppConfig.self, from: Data(broken.utf8)).channels.isEmpty)
    }

    @Test func oldOrangeActionsMigrateToChannels() throws {
        let json = #"""
        {"schemaVersion": 1, "profiles": [{"id": "default", "name": "G",
          "orange": {"tap": {"type": "cycleMode"}, "doubleTap": {"type": "none"}, "longPress": {"type": "none"}}}]}
        """#
        let orange = try #require(try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8)).profiles.first { $0.id == "default" }).orange
        #expect(orange.tap == .nextChannel)
        #expect(orange.doubleTap == .previousChannel)
        #expect(orange.longPress == .bindChannel)
        #expect(orange.veryLongPress == .clearChannels)
        let custom = #"{"profiles":[{"id":"d","name":"D","orange":{"tap":{"type":"key","keys":["escape"]}}}]}"#
        let profile = try #require(try JSONDecoder().decode(AppConfig.self, from: Data(custom.utf8)).profiles.first { $0.id == "d" })
        #expect(profile.orange.tap == .key(["escape"]))
        #expect(profile.orange.veryLongPress == .none)
    }

    @Test func idleLedShowsTheChannelYouAreOnAndTheSlot() {
        #expect(LedPattern.idle(channel: nil, slot: nil) == 0)
        #expect(LedPattern.idle(channel: 0, slot: nil) == 0b0000_0001)
        #expect(LedPattern.idle(channel: 3, slot: 5) == 0b0101_1000)
        #expect(LedPattern.idle(channel: nil, slot: 3) == 0b0011_0000)
    }
}

/// Which channel a window belongs to decides where the voice goes, with no jump (One-Pager 004).
@Suite struct ChannelFocusTests {
    private let claudeID = "com.anthropic.claudefordesktop"
    private func window(_ bundle: String, session: String? = nil, document: String? = nil, title: String? = nil) -> Channel {
        Channel(name: "w", bundleID: bundle, document: document, title: title, session: session)
    }

    @Test func wholeAppChannelMatchesAnyWindowOfThatApp() {
        let channel = Channel(name: "Claude", bundleID: claudeID)
        #expect(channel.matches(window: window(claudeID, title: "anything")))
        #expect(!channel.matches(window: window("other", title: "anything")))
        #expect(channel.specificity == 0)
    }

    @Test func sessionDocumentAndTitleMustBeEqual() {
        let session = Channel(name: "s", bundleID: claudeID, session: "local_a")
        #expect(session.matches(window: window(claudeID, session: "local_a")))
        #expect(!session.matches(window: window(claudeID, session: "local_b")))
        #expect(!session.matches(window: window(claudeID)))
        let document = Channel(name: "d", bundleID: "vs", document: "file:///a.md")
        #expect(document.matches(window: window("vs", document: "file:///a.md", title: "changed")))
        #expect(!document.matches(window: window("vs", document: "file:///b.md")))
        let titled = Channel(name: "t", bundleID: "w", title: "Doc1")
        #expect(titled.matches(window: window("w", title: "Doc1")))
        #expect(!titled.matches(window: window("w", title: "Doc2")))
        #expect(session.specificity == 3)
        #expect(document.specificity == 2)
        #expect(titled.specificity == 1)
    }

    @Test func theMostSpecificChannelWins() {
        var config = AppConfig()
        config.channels = [Channel(name: "Claude", bundleID: claudeID),
                           Channel(name: "Claude · api", bundleID: claudeID, session: "local_a")]
        let engine = ProfileEngine(config: config)
        #expect(engine.channelIndex(forWindow: window(claudeID, session: "local_a")) == 1)
        #expect(engine.channelIndex(forWindow: window(claudeID, session: "local_other")) == 0)
        #expect(engine.channelIndex(forWindow: window("mail")) == nil)
    }

    @Test func aWindowOfAnUnboundAppIsFree() {
        var config = AppConfig()
        config.channels = [Channel(name: "Claude", bundleID: claudeID)]
        var engine = ProfileEngine(config: config)
        engine.setFocus(0)
        engine.setFocus(engine.channelIndex(forWindow: window("com.apple.mail", title: "Inbox")))
        #expect(engine.channel == nil)
        #expect(engine.idleLEDs == 0)
    }
}

/// Orange held for 3 s is a deliberate gesture: it comes after the long press, only while held,
/// and never while talking.
@Suite struct VeryLongPressTests {
    private func press(_ r: inout GestureRecognizer, _ button: DeviceControl, at t: Double) -> [Gesture] {
        r.handle(button, active: true, at: t)
    }

    @Test func firesOnceAfterThreeSecondsWhileHeld() {
        var r = GestureRecognizer()
        _ = press(&r, .orange, at: 0)
        #expect(r.tick(at: 700) == [.longPress(.orange)])
        #expect(r.tick(at: 2500).isEmpty)
        #expect(r.tick(at: 3000) == [.veryLongPress(.orange)])
        #expect(r.tick(at: 4000).isEmpty)
        // Releasing afterwards is silent.
        #expect(r.handle(.orange, active: false, at: 4100).isEmpty)
    }

    @Test func releasingEarlierNeverFiresIt() {
        var r = GestureRecognizer()
        _ = press(&r, .orange, at: 0)
        _ = r.tick(at: 700)
        #expect(r.handle(.orange, active: false, at: 2000).isEmpty)
        #expect(r.tick(at: 5000).isEmpty)
    }

    @Test func notWhileTheHandleIsDown() {
        var r = GestureRecognizer()
        _ = r.handle(.handle, active: true, at: 0)
        _ = press(&r, .orange, at: 100)
        #expect(r.tick(at: 3500).allSatisfy { $0 != .veryLongPress(.orange) })
    }

    @Test func eachPressStartsOver() {
        var r = GestureRecognizer()
        _ = press(&r, .orange, at: 0)
        _ = r.tick(at: 700)
        _ = r.tick(at: 3000)
        _ = r.handle(.orange, active: false, at: 3100)
        _ = press(&r, .orange, at: 10_000)
        #expect(r.tick(at: 10_700) == [.longPress(.orange)])
        #expect(r.tick(at: 13_000) == [.veryLongPress(.orange)])
    }

    @Test func orangeHoldClearsChannelsByDefault() {
        let engine = ProfileEngine(config: AppConfig())
        #expect(engine.action(for: .veryLongPress(.orange)) == .clearChannels)
        #expect(engine.active.white.veryLongPress == Action.none)
    }
}

@Suite struct ChannelSessionTests {
    private let first = Channel(name: "Claude · api", bundleID: "com.anthropic.claudefordesktop", session: "local_aaaa1111")
    private let second = Channel(name: "Claude · web", bundleID: "com.anthropic.claudefordesktop", session: "local_bbbb2222")

    @Test func sessionsOfTheSameAppAreDifferentChannels() {
        #expect(!first.sameTarget(as: second))
        #expect(first.sameTarget(as: Channel(name: "renamed", bundleID: first.bundleID, session: "local_aaaa1111")))
    }

    @Test func sessionsAreNotMixedWithAppLevelChannels() {
        let app = Channel(name: "Claude", bundleID: first.bundleID, title: "Claude")
        #expect(!first.sameTarget(as: app))
        #expect(!app.sameTarget(as: first))
    }

    @Test func twoSessionsOfOneAppFillTwoChannels() {
        var engine = ProfileEngine(config: AppConfig())
        engine.bind(first)
        engine.bind(second)
        #expect(engine.config.channels == [first, second])
        engine.previousChannel()
        #expect(engine.channel?.session == "local_aaaa1111")
        engine.nextChannel()
        #expect(engine.channel?.session == "local_bbbb2222")
    }

    @Test func sessionSurvivesAConfigRoundTrip() throws {
        var config = AppConfig()
        config.channels = [first, second]
        let back = try JSONDecoder().decode(AppConfig.self, from: JSONEncoder().encode(config))
        #expect(back.channels.map(\.session) == ["local_aaaa1111", "local_bbbb2222"])
    }
}

@Suite struct NameMatcherTests {
    private let names = ["Claude · api-backend", "Codex · Crea diagramma CIA", "Mail", "TODO.md"]

    @Test func exactIgnoresCaseAndAccents() {
        #expect(NameMatcher.index(of: "mail", in: names) == 2)
        #expect(NameMatcher.index(of: "  TODO.MD ", in: names) == 3)
        #expect(NameMatcher.index(of: "todo.md", in: names) == 3)
        #expect(NameMatcher.index(of: "Codex · Crea diagramma CIA", in: names) == 1)
    }

    @Test func partAfterTheSeparatorAndContainment() {
        #expect(NameMatcher.index(of: "api-backend", in: names) == 0)
        #expect(NameMatcher.index(of: "codex", in: names) == 1)
        #expect(NameMatcher.index(of: "diagramma", in: names) == 1)
    }

    @Test func requestContainingTheName() {
        #expect(NameMatcher.index(of: "vai su mail ora", in: names) == 2)
        #expect(NameMatcher.index(of: "ok", in: ["a", "b"]) == nil)
    }

    @Test func nothingMatches() {
        #expect(NameMatcher.index(of: "", in: names) == nil)
        #expect(NameMatcher.index(of: "xyz", in: names) == nil)
        #expect(NameMatcher.index(of: "mail", in: []) == nil)
    }
}

@Suite struct IntentTests {
    @Test func everyProfileInterruptsWithEscapeAndGreyLongPressUsesIt() {
        let config = AppConfig()
        for profile in config.profiles {
            #expect(profile.intents["interrupt"] == .key(["escape"]))
        }
        #expect(Profile(id: "x", name: "x").grey.longPress == .intent("interrupt"))
    }

    @Test func oldGreyLongPressDefaultMigratesAndCustomOnesStay() throws {
        let old = #"{"profiles":[{"id":"default","name":"G","grey":{"longPress":{"type":"reinsertLast","variant":"raw"}}}]}"#
        let migrated = try #require(try JSONDecoder().decode(AppConfig.self, from: Data(old.utf8)).profiles.first { $0.id == "default" })
        #expect(migrated.grey.longPress == .intent("interrupt"))
        let custom = #"{"profiles":[{"id":"default","name":"G","grey":{"longPress":{"type":"key","keys":["ctrl+c"]}}}]}"#
        let kept = try #require(try JSONDecoder().decode(AppConfig.self, from: Data(custom.utf8)).profiles.first { $0.id == "default" })
        #expect(kept.grey.longPress == .key(["ctrl+c"]))
    }

    @Test func profileIntentsAreConfigurable() throws {
        let json = #"{"profiles":[{"id":"default","name":"G","intents":{"newSession":{"type":"key","keys":["cmd+n"]}}}]}"#
        let profile = try #require(try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8)).profiles.first { $0.id == "default" })
        #expect(profile.intents == ["newSession": .key(["cmd+n"])])
        let back = try JSONDecoder().decode(AppConfig.self, from: JSONEncoder().encode(AppConfig()))
        #expect(back.profiles.allSatisfy { $0.intents["interrupt"] == .key(["escape"]) })
    }

    @Test func intentActionRoundTrips() throws {
        let data = try JSONEncoder().encode([Action.intent("approve")])
        #expect(try JSONDecoder().decode([Action].self, from: data) == [.intent("approve")])
    }
}

