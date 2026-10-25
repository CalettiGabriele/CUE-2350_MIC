import Foundation

/// One control of the front window, as `read_ui` shows it to the model.
public struct UIElementInfo: Equatable, Sendable {
    public var id: String
    public var role: String
    public var title: String

    public init(id: String, role: String, title: String) {
        self.id = id
        self.role = role
        self.title = title
    }
}

public struct WindowInfo: Equatable, Sendable {
    public var id: String
    public var title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

/// What the interface tools do on the Mac (TDD voice command agent §3.3, phase 5): Accessibility
/// in the app, a fake screen in the evaluation. Ids are the ones the lists returned, valid for
/// one command.
public protocol MacUI: Sendable {
    /// Actionable controls of the front window; nil when the app exposes none.
    func uiElements() async -> [UIElementInfo]?
    func press(_ id: String) async -> ToolResult
    func setValue(_ id: String, text: String) async -> ToolResult
    /// Menu bar items of the front app as paths, e.g. "File › Export as PDF…"; nil when unreadable.
    func menuItems() async -> [String]?
    /// `path` is exactly one of `menuItems()`.
    func chooseMenuItem(_ path: String) async -> ToolResult
    /// Windows of the front app, the front one first.
    func windows() async -> [WindowInfo]
    func focusWindow(_ id: String) async -> ToolResult
    func closeWindow(_ id: String) async -> ToolResult
    func openApp(_ name: String) async -> ToolResult
    func openURL(_ url: URL) async -> ToolResult
}

/// What the interface tools of one run have seen, so a click can be checked against what
/// `read_ui` listed and its risk decided before it runs.
public final class UIState: @unchecked Sendable {
    private let lock = NSLock()
    private var _elements: [UIElementInfo] = []
    private var _menus: [String]?
    private var _windows: [WindowInfo] = []

    public init() {}

    public var elements: [UIElementInfo] {
        get { lock.withLock { _elements } }
        set { lock.withLock { _elements = newValue } }
    }
    public var menus: [String]? {
        get { lock.withLock { _menus } }
        set { lock.withLock { _menus = newValue } }
    }
    public var windows: [WindowInfo] {
        get { lock.withLock { _windows } }
        set { lock.withLock { _windows = newValue } }
    }
}

/// Words that make a click or a menu item risky, in the nine UI languages and the usual app
/// languages. Matching ignores case and accents and looks at whole words.
public enum Destructive {
    /// Never offered: these end sessions or lose work for good.
    public static let forbidden = [
        "quit", "log out", "shut down", "restart", "force quit", "empty trash", "erase",
        "esci", "chiudi sessione", "spegni", "riavvia", "svuota il cestino", "inizializza",
        "quitter", "fermer la session", "eteindre", "redemarrer", "vider la corbeille",
        "salir", "cerrar sesion", "reiniciar", "vaciar la papelera",
        "sair", "encerrar sessao", "desligar", "esvaziar o lixo",
        "beenden", "abmelden", "ausschalten", "neustart", "papierkorb entleeren",
    ]
    /// Allowed with a confirmation on the mic.
    public static let risky = [
        "delete", "remove", "send", "close", "discard", "move to trash", "archive", "submit", "publish",
        "post", "pay", "buy", "purchase", "confirm", "unsubscribe", "sign out", "erase", "clear",
        "elimina", "cancella", "rimuovi", "invia", "chiudi", "scarta", "sposta nel cestino", "archivia", "pubblica",
        "paga", "acquista", "conferma",
        "supprimer", "effacer", "retirer", "envoyer", "fermer", "jeter", "archiver", "publier", "payer", "acheter",
        "confirmer",
        "eliminar", "borrar", "quitar", "enviar", "cerrar", "descartar", "archivar", "publicar", "pagar", "comprar",
        "confirmar", "apagar",
        "excluir", "remover", "fechar", "arquivar",
        "loschen", "entfernen", "senden", "schliessen", "verwerfen", "archivieren", "veroffentlichen", "bezahlen",
        "kaufen", "bestatigen",
        "删除", "发送", "关闭", "移除", "削除", "送信", "閉じる", "удалить", "отправить", "закрыть",
    ]

    static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "ß", with: "ss")
    }

    static func contains(_ title: String, _ words: [String]) -> Bool {
        let t = " " + normalize(title).components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: " ") + " "
        return words.contains { word in
            let w = normalize(word)
            // CJK words have no spaces around them.
            return w.unicodeScalars.contains { $0.value > 0x2E80 } ? t.contains(w) : t.contains(" " + w + " ")
        }
    }

    public static func isForbidden(_ title: String) -> Bool { contains(title, forbidden) }
    public static func isRisky(_ title: String) -> Bool { isForbidden(title) || contains(title, risky) }
}

/// Menu paths and titles compared the way people say them: case, accents, "›" or ">", "…" or "...".
func looseKey(_ text: String) -> String {
    Destructive.normalize(text).replacingOccurrences(of: "…", with: "...")
        .replacingOccurrences(of: "›", with: ">")
        .components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
        .replacingOccurrences(of: " > ", with: ">").trimmingCharacters(in: CharacterSet(charactersIn: ". "))
}

extension BuiltInTools {
    /// The interface tools (phase 5). `open_url` is opt-in: it is only added when `allowOpenURL`.
    public static func interface(_ ui: MacUI, allowOpenURL: Bool = false) -> [AgentTool] {
        let state = UIState()
        var tools: [AgentTool] = [
            ReadUITool(ui: ui, state: state),
            ClickTool(ui: ui, state: state),
            SetValueTool(ui: ui, state: state),
            ListMenuItemsTool(ui: ui, state: state),
            ChooseMenuItemTool(ui: ui, state: state),
            ListWindowsTool(ui: ui, state: state),
            FocusWindowTool(ui: ui, state: state),
            CloseWindowTool(ui: ui, state: state),
            OpenAppTool(ui: ui),
        ]
        if allowOpenURL { tools.append(OpenURLTool(ui: ui)) }
        return tools
    }
}

struct ReadUITool: AgentTool {
    let ui: MacUI
    let state: UIState
    let risk = Risk.read
    static let limit = 60
    let spec = ToolSpec(
        name: "read_ui",
        description: "Lists the buttons, links and fields of the front window with ids for click and set_value.",
        inputSchema: Schema.object(["query": Schema.string("Optional: only controls whose name contains this.")]))

    func run(_ arguments: JSONValue, context: ToolContext) async -> ToolResult {
        guard let all = await ui.uiElements() else { return .failed("this app does not show its controls") }
        state.elements = all
        var shown = all
        if let query = arguments["query"]?.stringValue, !query.isEmpty {
            let q = looseKey(query)
            let matching = all.filter { looseKey($0.title).contains(q) }
            // A query that matches nothing (another language, a synonym) shows everything.
            if !matching.isEmpty { shown = matching }
        }
        guard !shown.isEmpty else { return .ok("no controls found") }
        let lines = shown.prefix(Self.limit).map { "\($0.id) \($0.role) «\($0.title)»" }
        let more = shown.count > Self.limit ? "\n… \(shown.count - Self.limit) more: use query" : ""
        return .ok(lines.joined(separator: "\n") + more)
    }
}

struct ClickTool: AgentTool {
    let ui: MacUI
    let state: UIState
    let risk = Risk.safe
    let spec = ToolSpec(
        name: "click",
        description: "Clicks a button, link or other control by its id from read_ui.",
        inputSchema: Schema.object(["element": Schema.string("An id from read_ui, e.g. e4.")], required: ["element"]))

    private func element(_ arguments: JSONValue) -> UIElementInfo? {
        let id = arguments["element"]?.stringValue ?? ""
        return state.elements.first { $0.id.caseInsensitiveCompare(id) == .orderedSame }
    }

    func risk(for arguments: JSONValue) -> Risk {
        element(arguments).map { Destructive.isRisky($0.title) } == true ? .risky : risk
    }

    func summary(for arguments: JSONValue) -> String {
        element(arguments).map { "click «\($0.title)»" } ?? "click"
    }

    func run(_ arguments: JSONValue, context: ToolContext) async -> ToolResult {
        guard let target = element(arguments) else { return .failed("unknown element: call read_ui first and use its ids") }
        if Destructive.isForbidden(target.title) { return .failed("«\(target.title)» is blocked for safety") }
        return await ui.press(target.id)
    }
}

struct SetValueTool: AgentTool {
    let ui: MacUI
    let state: UIState
    let risk = Risk.safe
    let spec = ToolSpec(
        name: "set_value",
        description: "Puts text into a field from read_ui (search box, subject, address) without clicking it first.",
        inputSchema: Schema.object(["element": Schema.string("An id from read_ui."), "text": Schema.string("The text.")],
                                   required: ["element", "text"]))

    func run(_ arguments: JSONValue, context: ToolContext) async -> ToolResult {
        let id = arguments["element"]?.stringValue ?? ""
        guard let target = state.elements.first(where: { $0.id.caseInsensitiveCompare(id) == .orderedSame }) else {
            return .failed("unknown element: call read_ui first and use its ids")
        }
        return await ui.setValue(target.id, text: arguments["text"]?.stringValue ?? "")
    }
}

struct ListMenuItemsTool: AgentTool {
    let ui: MacUI
    let state: UIState
    let risk = Risk.read
    static let limit = 80
    let spec = ToolSpec(
        name: "list_menu_items",
        description: "Lists the menu bar commands of the front app as paths for choose_menu_item, e.g. "
            + "File › Print…, View › Reload Page, Window › Minimize.",
        inputSchema: Schema.object(["filter": Schema.string("Optional: only paths that contain this word.")]))

    func run(_ arguments: JSONValue, context: ToolContext) async -> ToolResult {
        guard let all = await ui.menuItems() else { return .failed("this app does not show its menus") }
        let allowed = all.filter { !Destructive.isForbidden($0.components(separatedBy: "›").last ?? $0) }
        state.menus = allowed
        var shown = allowed
        if let filter = arguments["filter"]?.stringValue, !filter.isEmpty {
            let f = looseKey(filter)
            let matching = allowed.filter { looseKey($0).contains(f) }
            if !matching.isEmpty { shown = matching }
        }
        let more = shown.count > Self.limit ? "\n… \(shown.count - Self.limit) more: use filter" : ""
        return .ok(shown.prefix(Self.limit).joined(separator: "\n") + more)
    }
}

struct ChooseMenuItemTool: AgentTool {
    let ui: MacUI
    let state: UIState
    let risk = Risk.safe
    let spec = ToolSpec(
        name: "choose_menu_item",
        description: "Chooses a menu bar command of the front app by its path, e.g. Format › Style › Bold.",
        inputSchema: Schema.object(["path": Schema.string("A path from list_menu_items.")], required: ["path"]))

    func risk(for arguments: JSONValue) -> Risk {
        let last = (arguments["path"]?.stringValue ?? "").components(separatedBy: CharacterSet(charactersIn: "›>")).last ?? ""
        return Destructive.isRisky(last) ? .risky : risk
    }

    func summary(for arguments: JSONValue) -> String { arguments["path"]?.stringValue ?? spec.name }

    func run(_ arguments: JSONValue, context: ToolContext) async -> ToolResult {
        let path = arguments["path"]?.stringValue ?? ""
        if state.menus == nil {
            guard let all = await ui.menuItems() else { return .failed("this app does not show its menus") }
            state.menus = all.filter { !Destructive.isForbidden($0.components(separatedBy: "›").last ?? $0) }
        }
        let menus = state.menus ?? []
        let key = looseKey(path)
        let match = menus.first { looseKey($0) == key }
            // Only the last part ("Export as PDF…") is enough when it is unique.
            ?? { let ends = menus.filter { looseKey($0).hasSuffix(">" + key) }; return ends.count == 1 ? ends[0] : nil }()
        guard let match else {
            let word = key.components(separatedBy: ">").last ?? key
            let near = menus.filter { looseKey($0).contains(word.prefix(4)) }.prefix(8)
            return .failed("no menu item \(path)" + (near.isEmpty ? "; call list_menu_items" : "; close ones: " + near.joined(separator: "; ")))
        }
        return await ui.chooseMenuItem(match)
    }
}

struct ListWindowsTool: AgentTool {
    let ui: MacUI
    let state: UIState
    let risk = Risk.read
    let spec = ToolSpec(
        name: "list_windows",
        description: "Lists the windows of the front app, the front one first, with ids.",
        inputSchema: Schema.object([:]))

    func run(_ arguments: JSONValue, context: ToolContext) async -> ToolResult {
        let windows = await ui.windows()
        state.windows = windows
        return windows.isEmpty ? .ok("no windows") : .ok(windows.map { "\($0.id) «\($0.title)»" }.joined(separator: "\n"))
    }
}

/// focus_window and close_window share how a window is named: an id, or nothing for the front one.
private func resolveWindow(_ arguments: JSONValue, ui: MacUI, state: UIState) async -> WindowInfo? {
    if state.windows.isEmpty { state.windows = await ui.windows() }
    let id = arguments["window"]?.stringValue ?? ""
    if id.isEmpty { return state.windows.first }
    return state.windows.first { $0.id.caseInsensitiveCompare(id) == .orderedSame }
        ?? state.windows.first { looseKey($0.title).contains(looseKey(id)) }
}

struct FocusWindowTool: AgentTool {
    let ui: MacUI
    let state: UIState
    let risk = Risk.safe
    let spec = ToolSpec(
        name: "focus_window",
        description: "Brings a window of the front app forward (go to the window …), by its id from list_windows "
            + "or part of its title. Windows are not channels.",
        inputSchema: Schema.object(["window": Schema.string("An id from list_windows, or part of the title.")],
                                   required: ["window"]))

    func run(_ arguments: JSONValue, context: ToolContext) async -> ToolResult {
        guard let window = await resolveWindow(arguments, ui: ui, state: state) else {
            return .failed("no such window: call list_windows")
        }
        // The first window is the one in front already.
        if window.id == state.windows.first?.id { return .ok("«\(window.title)» is already in front") }
        return await ui.focusWindow(window.id)
    }
}

struct CloseWindowTool: AgentTool {
    let ui: MacUI
    let state: UIState
    let risk = Risk.risky
    let spec = ToolSpec(
        name: "close_window",
        description: "Closes a window: the front one when no window is given. The user confirms it on the mic. "
            + "Not for minimizing: that is Window › Minimize in the menus.",
        inputSchema: Schema.object(["window": Schema.string("Optional: an id from list_windows or part of the title.")]))

    func run(_ arguments: JSONValue, context: ToolContext) async -> ToolResult {
        guard let window = await resolveWindow(arguments, ui: ui, state: state) else {
            return .failed("no such window: call list_windows")
        }
        return await ui.closeWindow(window.id)
    }
}

struct OpenAppTool: AgentTool {
    let ui: MacUI
    let risk = Risk.safe
    let spec = ToolSpec(
        name: "open_app",
        description: "Opens an app, or brings it forward if it is running, by its name (in any language).",
        inputSchema: Schema.object(["name": Schema.string("The app's name, e.g. Notes, Safari, Calendar.")], required: ["name"]))

    func summary(for arguments: JSONValue) -> String { "open " + (arguments["name"]?.stringValue ?? "") }

    func run(_ arguments: JSONValue, context: ToolContext) async -> ToolResult {
        guard let name = arguments["name"]?.stringValue, !name.isEmpty else { return .failed("name is empty") }
        return await ui.openApp(name)
    }
}

struct OpenURLTool: AgentTool {
    static let schemes: Set<String> = ["http", "https", "claude", "codex"]
    let ui: MacUI
    let risk = Risk.risky
    let spec = ToolSpec(
        name: "open_url",
        description: "Opens a web address (http, https) or a claude:// or codex:// link. The user confirms it on the mic.",
        inputSchema: Schema.object(["url": Schema.string("The full address.")], required: ["url"]))

    func run(_ arguments: JSONValue, context: ToolContext) async -> ToolResult {
        guard let text = arguments["url"]?.stringValue, let url = URL(string: text),
              let scheme = url.scheme?.lowercased(), Self.schemes.contains(scheme) else {
            return .failed("only http, https, claude:// and codex:// addresses can be opened")
        }
        return await ui.openURL(url)
    }
}
