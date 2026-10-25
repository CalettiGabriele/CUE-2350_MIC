import FXMicCore
import Foundation

/// A tool that does nothing and says it worked: lets the agent loop run against a real model
/// without touching the Mac. Phase 3 replaces the answers with ones computed from the fake screen.
public final class SimulatedTool: AgentTool, @unchecked Sendable {
    public let spec: ToolSpec
    public let risk: Risk
    private let answer: String
    private let lock = NSLock()
    private var calls: [JSONValue] = []

    public init(_ spec: ToolSpec, risk: Risk, answer: String = "ok") {
        self.spec = spec
        self.risk = risk
        self.answer = answer
    }

    public func run(_ arguments: JSONValue, context: ToolContext) async -> ToolResult {
        lock.withLock { calls.append(arguments) }
        return .ok(answer)
    }

    /// A first set with the shapes of TDD §3.3, for the smoke test.
    public static func basic() -> [SimulatedTool] {
        [
            SimulatedTool(ToolSpec(name: "type_text", description: "Types text at the cursor.",
                                   inputSchema: Schema.object(["text": Schema.string("The text to type.")], required: ["text"])),
                          risk: .safe),
            SimulatedTool(ToolSpec(name: "press_keys", description: "Presses keyboard shortcuts in order, e.g. cmd+a, shift+return.",
                                   inputSchema: Schema.object(["keys": Schema.strings("Shortcuts such as cmd+a or return.")],
                                                              required: ["keys"])),
                          risk: .safe),
            SimulatedTool(ToolSpec(name: "replace_selection", description: "Replaces the selected text with the given text.",
                                   inputSchema: Schema.object(["text": Schema.string("The new text.")], required: ["text"])),
                          risk: .safe),
            SimulatedTool(ToolSpec(name: "read_focused_text", description: "Reads the text of the focused field.",
                                   inputSchema: Schema.object([:])),
                          risk: .read, answer: "Hi team,\nthe budget review is urgent and we need it by Friday.\nThanks"),
        ]
    }
}
