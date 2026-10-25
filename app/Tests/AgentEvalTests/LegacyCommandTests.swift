import Foundation
import Testing
import FXMicCore
@testable import AgentEvalKit

// The one-call command now lives in the evaluation only (TDD voice command agent §7).
@Suite struct LegacyCommandTests {
    @Test func parsesTextAndKeys() throws {
        let response = #"```json {"actions":[{"type":"text","text":"- "},{"type":"key","keys":["shift+return"]}]} ```"#
        #expect(try LegacyCommand.parse(response).get() == [.text("- "), .keys(["shift+return"])])
    }

    @Test func rejectsForbiddenAndGarbage() {
        #expect(LegacyCommand.parse(#"{"actions":[{"type":"key","keys":["cmd+q"]}]}"#) == .failure(.forbidden("cmd+q")))
        #expect(LegacyCommand.parse(#"{"actions":[{"type":"key","keys":["⌘+⌥+esc"]}]}"#) == .failure(.forbidden("⌘+⌥+esc")))
        #expect(LegacyCommand.parse("ok, fatto") == .failure(.notJSON))
        #expect(LegacyCommand.parse(#"{"actions":[{"type":"shell","cmd":"rm"}]}"#) == .failure(.notJSON))
    }

    @Test func leakedReasoningAndRepeatedJSON() throws {
        let response = "{\"actions\":[{\"type\":\"text\",\"text\":\"- \"}]}`\n</think>\n\n```json\n{\"actions\": [{\"type\": \"text\", \"text\": \"- \"}]}\n```"
        #expect(try LegacyCommand.parse(response).get() == [.text("- ")])
        #expect(try LegacyCommand.parse(#"nota {"x":1} poi {"actions":[{"type":"key","keys":["right"]}]}"#).get() == [.keys(["right"])])
        #expect(try LegacyCommand.parse(#"{"actions":[{"type":"text","text":"a } b"}]}"#).get() == [.text("a } b")])
    }

    @Test func parsesChannelSlotIntentAndSelectionSteps() throws {
        let response = #"{"actions":[{"type":"switchChannel","name":"Codex"},{"type":"runSlot","name":"/compact"},{"type":"intent","name":"interrupt"},{"type":"replaceSelection","text":"Hello"}]}"#
        #expect(try LegacyCommand.parse(response).get() == [.switchChannel("Codex"), .runSlot("/compact"), .intent("interrupt"), .replaceSelection("Hello")])
    }

    @Test func namedStepsNeedAName() {
        #expect(LegacyCommand.parse(#"{"actions":[{"type":"switchChannel"}]}"#) == .failure(.notJSON))
        #expect(LegacyCommand.parse(#"{"actions":[{"type":"intent","name":""}]}"#) == .failure(.notJSON))
        #expect(LegacyCommand.parse(#"{"actions":[{"type":"replaceSelection"}]}"#) == .failure(.notJSON))
    }

    @Test func emptyActionsMeanNothingToDo() throws {
        #expect(try LegacyCommand.parse(#"{"actions": []}"#).get() == [])
    }

    @Test func commandPromptIncludesHints() {
        let ctx = LegacyCommand.CommandContext(appName: "Claude", language: "auto", hints: "Markdown")
        let m = LegacyCommand.messages(context: ctx, transcript: "elenco puntato")
        #expect(m.system.contains("\"actions\""))
        #expect(m.system.contains("## App notes: Markdown"))
        #expect(m.system.contains("CHANNELS: (none)"))
        #expect(m.system.contains("SELECTION: (none)"))
        #expect(m.user == "elenco puntato")
    }

    @Test func commandPromptCarriesChannelsSlotsIntentsAndSelection() {
        let ctx = LegacyCommand.CommandContext(
            appName: "Claude", language: "it", channels: ["Claude · api", "Codex · infra"], slots: ["/compact", "/review"],
            intents: ["interrupt", "newSession"], selection: String(repeating: "a", count: 3000))
        let m = LegacyCommand.messages(context: ctx, transcript: "passa a codex")
        #expect(m.system.contains("CHANNELS: \"Claude · api\", \"Codex · infra\""))
        #expect(m.system.contains("SLOTS: \"/compact\", \"/review\""))
        #expect(m.system.contains("INTENTS: \"interrupt\", \"newSession\""))
        #expect(ctx.selection?.count == LegacyCommand.CommandContext.maxSelection)
        #expect(!m.system.contains("(none)\nSELECTION: (none)"))
    }
}
