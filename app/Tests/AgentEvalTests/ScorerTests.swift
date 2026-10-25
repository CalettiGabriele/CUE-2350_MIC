import Foundation
import Testing
import FXMicCore
@testable import AgentEvalKit

@Suite struct ScorerTests {
    let screen = Screen(app: "Claude", profile: "claude-desktop",
                        channels: ["Claude · api-project", "Codex · fxmic-bridge"], selection: "buon lavoro a tutti")

    func evalCase(_ expect: [[StepMatcher]]) -> EvalCase {
        EvalCase(id: "t", group: "today", category: "keys", lang: "en", command: "test", screen: "s", expect: expect)
    }

    @Test func consecutiveKeysAreMergedAndCanonical() {
        let got = Scorer.outcome([
            EvalAction(tool: "read_ui"), EvalAction(tool: "press_keys", keys: ["CMD+A"]),
            EvalAction(tool: "press_keys", keys: ["backspace"]), EvalAction(tool: "finish", args: ["summary": "ok"]),
        ])
        #expect(got == [EvalAction(tool: "press_keys", keys: ["cmd+a", "delete"])])
        #expect(Scorer.canonicalKey("shift+cmd+Left") == "cmd+shift+left")
        #expect(Scorer.canonicalKey("esc") == "escape")
    }

    @Test func anyAlternativePasses() {
        let c = evalCase([[StepMatcher(tool: "press_keys", keys: ["return"])],
                          [StepMatcher(tool: "click", args: ["element": "e3"])]])
        #expect(Scorer.passes([EvalAction(tool: "click", args: ["element": "E3"])], c, screen: screen))
        #expect(!Scorer.passes([EvalAction(tool: "press_keys", keys: ["shift+return"])], c, screen: screen))
        #expect(!Scorer.passes([], c, screen: screen))
    }

    @Test func emptyAlternativeMeansNoAction() {
        let c = evalCase([[]])
        #expect(Scorer.passes([], c, screen: screen))
        #expect(Scorer.passes([EvalAction(tool: "finish", args: ["summary": "cannot"])], c, screen: screen))
        #expect(!Scorer.passes([EvalAction(tool: "type_text", args: ["text": "sunny"])], c, screen: screen))
    }

    @Test func textIsComparedLoosely() {
        let exact = evalCase([[StepMatcher(tool: "type_text", text: "see you soon")]])
        #expect(Scorer.passes([EvalAction(tool: "type_text", args: ["text": "See you soon!"])], exact, screen: screen))
        let groups = evalCase([[StepMatcher(tool: "replace_selection", textIncludes: ["good", ["everyone", "all"]],
                                            textExcludes: ["buon"], shorterThanSelection: true)]])
        #expect(Scorer.passes([EvalAction(tool: "replace_selection", args: ["text": "Good job all"])], groups, screen: screen))
        #expect(!Scorer.passes([EvalAction(tool: "replace_selection", args: ["text": "Good work, everyone, really"])],
                               groups, screen: screen))
        #expect(!Scorer.passes([EvalAction(tool: "replace_selection", args: ["text": "buon all good"])], groups, screen: screen))
    }

    @Test func menuPathsIgnoreSeparatorStyle() {
        let c = evalCase([[StepMatcher(tool: "choose_menu_item", args: ["path": "File › Export as PDF…"])]])
        #expect(Scorer.passes([EvalAction(tool: "choose_menu_item", args: ["path": "file > export as pdf..."])], c, screen: screen))
    }

    @Test func channelNamesResolveLikeTheApp() {
        let c = evalCase([[StepMatcher(tool: "switch_channel", name: "Codex · fxmic-bridge")]])
        #expect(Scorer.passes([EvalAction(tool: "switch_channel", args: ["name": "codex"])], c, screen: screen))
        #expect(!Scorer.passes([EvalAction(tool: "switch_channel", args: ["name": "api-project"])], c, screen: screen))
        let skill = evalCase([[StepMatcher(tool: "run_skill", name: "New chat")]])
        #expect(Scorer.passes([EvalAction(tool: "run_skill", args: ["name": "new chat"])], skill, screen: screen))
    }

    @Test func legacyStepsMapToTools() {
        #expect(LegacyEngine.action(.keys(["cmd+a"])) == EvalAction(tool: "press_keys", keys: ["cmd+a"]))
        #expect(LegacyEngine.action(.runSlot("/review")) == EvalAction(tool: "run_skill", args: ["name": "/review"]))
        #expect(LegacyEngine.action(.intent("interrupt")) == EvalAction(tool: "run_intent", args: ["name": "interrupt"]))
        let context = LegacyEngine.context(Screen(app: "Terminal", profile: "coding-agent", extraIntents: ["newSession"]))
        #expect(context.intents == ["interrupt", "newSession"])
        #expect(context.slots.contains("/review"))
    }
}

@Suite struct CorpusTests {
    static let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("scripts/agent-eval/corpus.json")

    @Test func corpusIsValid() throws {
        let corpus = try Corpus.load(Self.url)
        #expect(corpus.problems() == [])
        #expect(corpus.cases.count >= 60)
        #expect(Set(corpus.cases.map(\.lang)) == ["it", "en", "fr", "es"])
        for lang in ["it", "en", "fr", "es"] {
            #expect(corpus.cases.filter { $0.lang == lang }.count >= 12, "too few cases in \(lang)")
        }
        let profiles = Set(Profile.defaults.map(\.id))
        for screen in corpus.screens.values { #expect(profiles.contains(screen.profile)) }
    }

    /// Every channel or skill named in an expectation must exist on its screen, or the case can never pass.
    @Test func expectedNamesExist() throws {
        let corpus = try Corpus.load(Self.url)
        for c in corpus.cases {
            let screen = corpus.screens[c.screen]!
            for step in c.expect.joined() {
                guard let name = step.name else { continue }
                switch step.tool {
                case "switch_channel":
                    #expect(NameMatcher.index(of: name, in: screen.channels ?? []) != nil, "\(c.id): \(name)")
                case "run_skill":
                    let slots = Profile.defaults.first { $0.id == screen.profile }!.slots.map(\.name)
                    #expect(NameMatcher.index(of: name, in: slots) != nil, "\(c.id): \(name)")
                default: break
                }
            }
        }
    }
}
