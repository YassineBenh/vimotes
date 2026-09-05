import AppKit

@MainActor
enum SettingsViews {
  static func makeTab(label: String, symbol: String, view: NSView) -> NSTabViewItem {
    let viewController = NSViewController()
    viewController.view = view
    viewController.preferredContentSize = NSSize(width: 620, height: 480)
    let item = NSTabViewItem(viewController: viewController)
    item.label = label
    item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
    return item
  }

  static func makePage(
    title: String,
    detail: String,
    symbol: String,
    color: NSColor,
    content pageContent: NSView,
    footer: NSView? = nil,
    constraints: [NSLayoutConstraint] = []
  ) -> NSView {
    let root = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 620, height: 480))
    root.material = .contentBackground
    root.state = .active

    let header = makeHeader(title: title, detail: detail, symbol: symbol, color: color)
    var views = [header, pageContent]
    if let footer {
      views.append(footer)
    }
    let stack = NSStackView(views: views)
    stack.orientation = .vertical
    stack.alignment = .width
    stack.spacing = 20
    stack.translatesAutoresizingMaskIntoConstraints = false
    root.addSubview(stack)

    NSLayoutConstraint.activate(
      [
        stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
        stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28),
        stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 24),
        stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -22),
      ] + constraints)
    return root
  }

  static func makeHeader(
    title: String,
    detail: String,
    symbol: String,
    color: NSColor
  ) -> NSView {
    let icon = NSImageView()
    icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
    icon.contentTintColor = color
    icon.symbolConfiguration = .init(pointSize: 21, weight: .medium)

    let iconBackground = NSView()
    iconBackground.wantsLayer = true
    iconBackground.layer?.backgroundColor = color.withAlphaComponent(0.12).cgColor
    iconBackground.layer?.cornerRadius = 10
    iconBackground.addSubview(icon)
    icon.translatesAutoresizingMaskIntoConstraints = false

    let titleField = NSTextField(labelWithString: title)
    titleField.font = .systemFont(ofSize: 18, weight: .semibold)
    let detailField = NSTextField(labelWithString: detail)
    detailField.font = .systemFont(ofSize: 12)
    detailField.textColor = .secondaryLabelColor
    let text = NSStackView(views: [titleField, detailField])
    text.orientation = .vertical
    text.alignment = .leading
    text.spacing = 3
    let header = NSStackView(views: [iconBackground, text])
    header.orientation = .horizontal
    header.alignment = .centerY
    header.spacing = 13

    NSLayoutConstraint.activate([
      iconBackground.widthAnchor.constraint(equalToConstant: 42),
      iconBackground.heightAnchor.constraint(equalToConstant: 42),
      icon.centerXAnchor.constraint(equalTo: iconBackground.centerXAnchor),
      icon.centerYAnchor.constraint(equalTo: iconBackground.centerYAnchor),
    ])
    return header
  }

  static func makeDivider() -> NSBox {
    let divider = NSBox()
    divider.boxType = .separator
    return divider
  }
}
