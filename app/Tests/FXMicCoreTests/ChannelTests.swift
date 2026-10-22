import Foundation
import Testing
@testable import FXMicCore

@Suite struct ChannelTests {
    private let claude = Channel(name: "Claude", bundleID: "com.anthropic.claudefordesktop", title: "Claude")
    private let notes = Channel(name: "Code · TODO.md", bundleID: "com.microsoft.VSCode",
                                document: "file:///tmp/TODO.md", title: "TODO.md")
    private let word = Channel(name: "Word", bundleID: "com.microsoft.Word", title: "Doc1")

    @Test func startsOnAnEmptyPosition() {
        let engine = ProfileEngine(config: AppConfig())
        #expect(engine.channelPositions == 1)
        #expect(engine.channelPosition == 0)
        #expect(engine.channel == nil)
        #expect(engine.idleLEDs == 0b0000_0001)
    }

    @Test func bindingFillsPositionsAndAddsAnEmptyOne() {
        var engine = ProfileEngine(config: AppConfig())
        #expect(engine.bind(claude) == 0)
        #expect(engine.channelPositions == 2)
        engine.nextChannel()
        #expect(engine.channel == nil)
        #expect(engine.bind(notes) == 1)
        #expect(engine.config.channels == [claude, notes])
        #expect(engine.idleLEDs == 0b0000_0010)
    }

    @Test func cyclesThroughBoundChannelsAndTheEmptyPosition() {
        var engine = ProfileEngine(config: AppConfig())
        engine.bind(claude)
        engine.nextChannel(); engine.bind(notes)
        engine.nextChannel(); engine.bind(word)
        #expect(engine.channelPositions == 4)
        var seen: [Int] = [engine.channelPosition]
        for _ in 0..<4 { engine.nextChannel(); seen.append(engine.channelPosition) }
        #expect(seen == [2, 3, 0, 1, 2])
        engine.previousChannel(); engine.previousChannel(); engine.previousChannel()
        #expect(engine.channelPosition == 3)
    }

    @Test func maximumFourChannels() {
        var engine = ProfileEngine(config: AppConfig())
        for i in 0..<6 {
            engine.bind(Channel(name: "A\(i)", bundleID: "app.\(i)", title: "t"))
            engine.nextChannel()
        }
        #expect(engine.config.channels.count == 4)
        #expect(engine.channelPositions == 4)
    }

    @Test func rebindingTheSameWindowDoesNotDuplicate() {
        var engine = ProfileEngine(config: AppConfig())
        engine.bind(claude)
        engine.nextChannel(); engine.bind(notes)
        engine.select(channel: 0)
        #expect(engine.bind(notes) == 1)
        #expect(engine.config.channels == [claude, notes])
        // Same document, different window title: still the same channel.
        var renamed = notes
        renamed.title = "TODO.md — edited"
        engine.select(channel: 0)
        #expect(engine.bind(renamed) == 1)
        #expect(engine.config.channels.count == 2)
    }

    @Test func bindingOnABoundPositionReplacesIt() {
        var engine = ProfileEngine(config: AppConfig())
        engine.bind(claude)
        engine.bind(word)
        #expect(engine.config.channels == [word])
    }

    @Test func unbindRemovesAndKeepsAValidPosition() {
        var engine = ProfileEngine(config: AppConfig())
        engine.bind(claude)
        engine.nextChannel(); engine.bind(notes)
        let removed = engine.unbindChannel()
        #expect(removed)
        #expect(engine.config.channels == [claude])
        #expect(engine.channelPosition == 1)
        #expect(engine.channel == nil)
        let removedAgain = engine.unbindChannel()
        #expect(!removedAgain)
    }

    @Test func reloadClampsThePosition() {
        var engine = ProfileEngine(config: AppConfig())
        engine.bind(claude)
        engine.nextChannel(); engine.bind(notes)
        engine.reload(AppConfig())
        #expect(engine.channelPosition == 0)
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
        let custom = #"{"profiles":[{"id":"d","name":"D","orange":{"tap":{"type":"key","keys":["escape"]}}}]}"#
        let profile = try #require(try JSONDecoder().decode(AppConfig.self, from: Data(custom.utf8)).profiles.first { $0.id == "d" })
        #expect(profile.orange.tap == .key(["escape"]))
    }

    @Test func idleLedShowsChannelAndSlot() {
        #expect(LedPattern.idle(channel: 0, slot: nil) == 0b0000_0001)
        #expect(LedPattern.idle(channel: 3, slot: 5) == 0b0101_1000)
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
        engine.nextChannel()
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
