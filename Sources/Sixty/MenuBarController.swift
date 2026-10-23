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
final class MenuBarController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let statusLine = NSMenuItem()
    private let breaksLine = NSMenuItem()
    private let escapesLine = NSMenuItem()
    private var shown: MenuContent?

    override init() {
        super.init()
        let menu = NSMenu()
        menu.autoenablesItems = false
        for line in [statusLine, breaksLine, escapesLine] {
            line.isEnabled = false
            menu.addItem(line)
        }
        menu.addItem(.separator())
        menu.addItem(link(L("About Sixty") + " " + Links.version, #selector(openWebsite)))
        menu.addItem(link(L("How to turn Sixty off"), #selector(openTurnOff)))
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

    @objc private func openTurnOff() {
        NSWorkspace.shared.open(Links.turnOff)
    }
}
