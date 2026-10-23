import AppKit

struct MenuContent: Equatable {
    var title: String
    var symbol: String
    var status: String
    var breaksToday: String
    var escapesLeft: String
}

/// Icon and minutes to the next break. Read-only lines and two links. No Quit, on purpose.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let statusLine = NSMenuItem()
    private let breaksLine = NSMenuItem()
    private let escapesLine = NSMenuItem()
    private var shown: MenuContent?
    /// "Take a Break Now". Set by the controller.
    var onBreakNow: (() -> Void)?
    #if APP_STORE
    private let loginToggle = NSMenuItem()
    private let quitPrompt = QuitPrompt()
    #endif

    override init() {
        super.init()
        let menu = NSMenu()
        menu.autoenablesItems = false
        for line in [statusLine, breaksLine, escapesLine] {
            line.isEnabled = false
            menu.addItem(line)
        }
        menu.addItem(.separator())
        menu.addItem(link(L("Take a Break Now"), #selector(breakNow)))
        menu.addItem(.separator())
        menu.addItem(link(L("About Sixty") + " " + Links.version, #selector(openWebsite)))
        #if APP_STORE
        loginToggle.title = L("Start at Login")
        loginToggle.action = #selector(toggleLogin)
        loginToggle.target = self
        menu.addItem(loginToggle)
        menu.addItem(.separator())
        menu.addItem(link(L("Quit Sixty…"), #selector(quit)))
        #else
        menu.addItem(link(L("How to turn Sixty off"), #selector(openTurnOff)))
        #endif
        menu.delegate = self
        item.menu = menu
        item.button?.imagePosition = .imageLeading
    }

    func render(_ content: MenuContent) {
        guard content != shown else { return }
        if content.symbol != shown?.symbol {
            let image = NSImage(systemSymbolName: content.symbol, accessibilityDescription: "Sixty")
            image?.isTemplate = true
            item.button?.image = image
        }
        item.button?.title = content.title
        statusLine.title = content.status
        breaksLine.title = content.breaksToday
        escapesLine.title = content.escapesLeft
        shown = content
    }

    private func link(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func openWebsite() {
        NSWorkspace.shared.open(Links.website)
    }

    @objc private func breakNow() {
        onBreakNow?()
    }

    @objc private func openTurnOff() {
        NSWorkspace.shared.open(Links.turnOff)
    }

    func menuWillOpen(_ menu: NSMenu) {
        #if APP_STORE
        loginToggle.state = LoginItem.isEnabled ? .on : .off
        #endif
    }

    #if APP_STORE
    @objc private func toggleLogin() {
        LoginItem.setEnabled(!LoginItem.isEnabled)
    }

    @objc private func quit() {
        quitPrompt.show()
    }
    #endif
}
