import Foundation
import Testing
@testable import FXMicCore

@Suite struct ConfigTests {
    @Test func emptyJSONGivesDefaults() throws {
        let config = try JSONDecoder().decode(AppConfig.self, from: Data("{}".utf8))
        #expect(config == AppConfig())
        #expect(config.profiles.map(\.id) == ["claude-desktop", "coding-agent", "default"])
        #expect(config.schemaVersion == 4)
    }

    @Test func partialJSONKeepsOtherDefaults() throws {
        let json = #"{"llm": {"model": "qwen3:4b"}, "speech": {"language": "it"}}"#
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        #expect(config.llm.model == "qwen3:4b")
        #expect(config.llm.active.baseURL == "http://localhost:11434/v1")
        #expect(config.speech.language == "it")
    }

    @Test func roundTripKeepsEverything() throws {
        let config = AppConfig()
        let data = try JSONEncoder().encode(config)
        #expect(try JSONDecoder().decode(AppConfig.self, from: data) == config)
    }

    @Test func actionsRoundTrip() throws {
        let actions: [Action] = [.key(["cmd+a", "delete"]), .text("/clear\n"), .undoLastInsertion,
                                 .reinsertLast(raw: false), .cancel, .editSelection, .nextChannel, .previousChannel, .bindChannel, .clearChannels, .intent("interrupt"), .cycleMode, .resetMode,
                                 .nextSlot, .previousSlot, .clearSlot, .runSlot, .none]
        let data = try JSONEncoder().encode(actions)
        #expect(try JSONDecoder().decode([Action].self, from: data) == actions)
    }

    @Test func schema1ProfileIsMigrated() throws {
        let json = #"""
        {"profiles": [{"id": "mail", "name": "Mail", "apps": ["com.apple.mail"],
          "modes": [{"name":"Pulito","prompt":"P1"},{"name":"Email","prompt":"P2"}],
          "styles": [{"name":"Neutro","prompt":""}],
          "white": {"tap": {"type": "cycleStyle"}},
          "grey": {"tap": {"type": "key", "keys": ["return"]}}}]}
        """#
        let mail = try #require(try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8)).profiles.first { $0.id == "mail" })
        #expect(mail.interaction.enhancePrompt == "P1")
        #expect(mail.slots == [.llm("Email", "P2")])
        #expect(mail.white.tap == .nextSlot)
        #expect(mail.white.doubleTap == .previousSlot)
        #expect(mail.grey.tap == .runSlot)
        #expect(mail.orange.longPress == .bindChannel)
    }

    @Test func schema1FileGetsNewBuiltInProfiles() throws {
        let json = #"{"schemaVersion": 1, "profiles": [{"id": "default", "name": "Generale"}]}"#
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        #expect(config.profiles.map(\.id) == ["claude-desktop", "coding-agent", "default"])
        let v2 = #"{"schemaVersion": 2, "profiles": [{"id": "default", "name": "Generale"}]}"#
        #expect(try JSONDecoder().decode(AppConfig.self, from: Data(v2.utf8)).profiles.map(\.id) == ["default"])
    }

    @Test func slotsAreCappedAtFifteen() throws {
        let slots = (1...20).map { #"{"name":"s\#($0)","kind":"run","action":{"type":"none"}}"# }.joined(separator: ",")
        let json = #"{"profiles":[{"id":"x","slots":[\#(slots)]}]}"#
        let profile = try #require(try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8)).profiles.first { $0.id == "x" })
        #expect(profile.slots.count == 15)
    }

    @Test func invalidLedMapFallsBack() throws {
        let json = #"{"device": {"ledMap": [0, 0, 1, 2, 3, 4, 5, 6]}}"#
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        #expect(config.device.ledMap == Array(0..<8))
    }

    @Test func templateFill() {
        #expect(Slot.template("T", "Riassumi:\n{{testo}}").fill("ciao") == "Riassumi:\nciao")
        let old = try! JSONDecoder().decode(Slot.self, from: Data(#"{"name": "S", "kind": "template", "template": "Sum up: {{testo}}"}"#.utf8))
        #expect(old.template == "Sum up: {{text}}")
        #expect(Slot.template("T", "Traduci").fill("ciao") == "Traduci ciao")
    }

    @Test func uiSettingsDecodeWithDefaults() throws {
        let json = #"{"ui": {"menuBarIcon": "file", "menuBarIconFile": "/tmp/x.svg"}}"#
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        #expect(config.ui.menuBarIcon == "file")
        #expect(MenuBarIconPreset(rawValue: "waveform")?.symbolName == "waveform")
    }

    @Test func localEndpointDetection() {
        var llm = AppConfig.LLM()
        #expect(llm.isLocal)
        llm.active.baseURL = "https://api.example.com/v1"
        #expect(!llm.isLocal)
    }
}

@Suite struct KeyComboTests {
    @Test func parsesModifiersAndKeys() {
        #expect(KeyCombo("cmd+shift+return") == KeyCombo("⌘+⇧+return"))
        #expect(KeyCombo("ctrl+u")?.modifiers == [.control])
        #expect(KeyCombo("escape")?.modifiers == [])
    }

    @Test func rejectsUnknown() {
        #expect(KeyCombo("hyper+a") == nil)
        #expect(KeyCombo("cmd+banana") == nil)
    }
}

@Suite struct ProfileEngineTests {
    @Test func picksProfileByBundleID() {
        var engine = ProfileEngine(config: AppConfig())
        #expect(engine.active.id == "default")
        let toClaude = engine.activate(bundleID: Profile.claudeDesktopID)
        #expect(toClaude)
        #expect(engine.active.id == "claude-desktop")
        let toTerminal = engine.activate(bundleID: "com.googlecode.iterm2")
        #expect(toTerminal)
        #expect(engine.active.id == "coding-agent")
    }

    @Test func orangeCyclesInteractionModesAndResets() {
        var engine = ProfileEngine(config: AppConfig())
        #expect(engine.mode == .dictation)
        engine.cycleMode()
        #expect(engine.mode == .enhanced)
        engine.cycleMode()
        #expect(engine.mode == .command)
        engine.cycleMode()
        #expect(engine.mode == .computerUse)
        engine.cycleMode()
        #expect(engine.mode == .dictation)
        engine.cycleMode()
        engine.resetMode()
        #expect(engine.mode == .dictation)
    }

    @Test func disabledModesAreSkipped() {
        var config = AppConfig()
        config.profiles[2].interaction.enabled = [.dictation, .enhanced]
        var engine = ProfileEngine(config: config)
        engine.cycleMode()
        engine.cycleMode()
        #expect(engine.mode == .dictation)
    }

    @Test func whiteWalksSlotsThroughNone() {
        var engine = ProfileEngine(config: AppConfig())   // "Generale": 4 slots
        #expect(engine.slotNumber == nil)
        engine.nextSlot()
        #expect(engine.slotNumber == 1)
        #expect(engine.slotName == "Email")
        for _ in 0..<3 { engine.nextSlot() }
        #expect(engine.slotNumber == 4)
        engine.nextSlot()
        #expect(engine.slotNumber == nil)
        engine.previousSlot()
        #expect(engine.slotNumber == 4)
        engine.clearSlot()
        #expect(engine.slot == nil)
    }

    @Test func selectionIsPerProfile() {
        var engine = ProfileEngine(config: AppConfig())
        engine.cycleMode()
        engine.nextSlot()
        engine.activate(bundleID: Profile.claudeDesktopID)
        #expect(engine.mode == .dictation)
        #expect(engine.slot == nil)
        engine.activate(bundleID: nil)
        #expect(engine.mode == .enhanced)
        #expect(engine.slotNumber == 1)
    }

    @Test func gestureActionsComeFromActiveProfile() {
        var engine = ProfileEngine(config: AppConfig())
        #expect(engine.action(for: .tap(.orange)) == .nextChannel)
        #expect(engine.action(for: .doubleTap(.orange)) == .previousChannel)
        #expect(engine.action(for: .longPress(.orange)) == .bindChannel)
        #expect(engine.action(for: .tap(.white)) == .nextSlot)
        #expect(engine.action(for: .doubleTap(.white)) == .previousSlot)
        #expect(engine.action(for: .longPress(.white)) == .clearSlot)
        #expect(engine.action(for: .tap(.grey)) == .runSlot)
        #expect(engine.action(for: .pttDown) == nil)
        engine.activate(bundleID: "com.mitchellh.ghostty")
        #expect(engine.action(for: .longPress(.grey)) == .key(["escape"]))
    }
}

@Suite struct LedPatternTests {
    @Test func idleShowsModeAndBinarySlot() {
        #expect(LedPattern.idle(mode: .dictation, slot: nil) == 0b0000_0001)
        #expect(LedPattern.idle(mode: .command, slot: 1) == 0b0001_0100)
        #expect(LedPattern.idle(mode: .enhanced, slot: 5) == 0b0101_0010)
        #expect(LedPattern.white(slot: 15) == 0xF0)
    }

    @Test func kittSweepsUpAndDown() {
        let reds = (0..<7).map { LedPattern.kitt(frame: $0, slot: nil) }
        #expect(reds == [0b0001, 0b0010, 0b0100, 0b1000, 0b0100, 0b0010, 0b0001])
    }

    @Test func bootRunsDownTheColumnOnce() {
        let masks = (0..<(LedPattern.bootFrames + 1)).map { LedPattern.boot(frame: $0) }
        #expect(masks == [0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x00])
    }

    @Test func physicalMapping() {
        #expect(LedPattern.physical(0b0000_0001, map: Array(0..<8)) == 0b0000_0001)
        #expect(LedPattern.physical(0b0000_0001, map: [3, 2, 1, 0, 4, 5, 6, 7]) == 0b0000_1000)
        #expect(LedPattern.physical(0b1000_0000, map: [0, 1, 2, 3, 7, 6, 5, 4]) == 0b0001_0000)
    }
}


@Suite struct PromptComposerTests {
    let context = PromptComposer.Context(appName: "Claude", language: "it", date: "2026-10-16")

    @Test func composesEnhancePrompt() {
        let m = PromptComposer.messages(base: "BASE", mode: PromptPreset(name: "E", prompt: "Email"), style: nil,
                                        context: context, transcript: "ciao", selection: nil)
        #expect(m.system.hasPrefix("BASE\n\n## Instruction: Email"))
        #expect(m.user == "ciao")
    }

    @Test func cleanStripsThinkingAndQuotes() {
        #expect(PromptComposer.clean("<think>hmm</think>\n  \"Ciao a tutti\"  ") == "Ciao a tutti")
    }
}
