import AppKit

extension SettingsViews {
  static func makeGeneralView(
    menuBarSwitch: NSSwitch,
    notesWindowSwitch: NSSwitch,
    launchAtLoginSwitch: NSSwitch,
    launchAtLoginDetail: NSTextField,
    automaticUpdatesSwitch: NSSwitch,
    githubButton: NSButton,
    reportIssueButton: NSButton
  ) -> NSView {
    let menuBarRow = makeOptionRow(
      title: "Show mode in the menu bar",
      detail: "Display NORMAL, INSERT, or VISUAL next to the ViMotes icon while Notes is active.",
      toggle: menuBarSwitch
    )
    let notesWindowRow = makeOptionRow(
      title: "Show mode inside Apple Notes",
      detail:
        "Anchor a compact mode indicator to the lower-right corner of the active Notes window.",
      toggle: notesWindowSwitch
    )
    let launchAtLoginRow = makeOptionRow(
      title: "Launch ViMotes at login",
      detailField: launchAtLoginDetail,
      toggle: launchAtLoginSwitch
    )
    let updateRow = makeOptionRow(
      title: "Automatically check for updates",
      detail: "Check for signed updates; installation always requires your approval.",
      toggle: automaticUpdatesSwitch
    )
    let options = NSStackView(views: [
      menuBarRow,
      makeDivider(),
      notesWindowRow,
      makeDivider(),
      launchAtLoginRow,
      makeDivider(),
      updateRow,
    ])
    options.orientation = .vertical
    options.alignment = .width
    options.spacing = 0

    let openSourceCard = makeOpenSourceCard(
      githubButton: githubButton,
      reportIssueButton: reportIssueButton
    )
    let content = NSStackView(views: [options, openSourceCard])
    content.orientation = .vertical
    content.alignment = .width
    content.spacing = 16

    let version =
      Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
      as? String ?? "Development"
    let footer = NSTextField(
      labelWithString: "ViMotes \(version) · Free and open source under the MIT License."
    )
    footer.font = .systemFont(ofSize: 11)
    footer.textColor = .secondaryLabelColor

    return makePage(
      title: "General",
      detail: "Choose how ViMotes appears and starts on your Mac.",
      symbol: "character.cursor.ibeam",
      color: .systemBlue,
      content: content,
      footer: footer,
      constraints: [
        menuBarRow.heightAnchor.constraint(equalToConstant: 56),
        notesWindowRow.heightAnchor.constraint(equalToConstant: 56),
        launchAtLoginRow.heightAnchor.constraint(equalToConstant: 56),
        updateRow.heightAnchor.constraint(equalToConstant: 56),
        openSourceCard.heightAnchor.constraint(equalToConstant: 76),
      ]
    )
  }

  static func makeOptionRow(
    title: String,
    detail: String,
    toggle: NSSwitch
  ) -> NSView {
    let detailField = NSTextField(wrappingLabelWithString: detail)
    return makeOptionRow(title: title, detailField: detailField, toggle: toggle)
  }

  static func makeOptionRow(
    title: String,
    detailField: NSTextField,
    toggle: NSSwitch
  ) -> NSView {
    let titleField = NSTextField(labelWithString: title)
    titleField.font = .systemFont(ofSize: 13, weight: .medium)
    detailField.font = .systemFont(ofSize: 11)
    detailField.textColor = .secondaryLabelColor
    detailField.maximumNumberOfLines = 2
    let text = NSStackView(views: [titleField, detailField])
    text.orientation = .vertical
    text.alignment = .leading
    text.spacing = 3
    let row = NSView()
    row.addSubview(text)
    row.addSubview(toggle)
    text.translatesAutoresizingMaskIntoConstraints = false
    toggle.translatesAutoresizingMaskIntoConstraints = false
    text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    toggle.setContentHuggingPriority(.required, for: .horizontal)
    NSLayoutConstraint.activate([
      text.leadingAnchor.constraint(equalTo: row.leadingAnchor),
      text.centerYAnchor.constraint(equalTo: row.centerYAnchor),
      text.trailingAnchor.constraint(
        lessThanOrEqualTo: toggle.leadingAnchor,
        constant: -16
      ),
      toggle.trailingAnchor.constraint(equalTo: row.trailingAnchor),
      toggle.centerYAnchor.constraint(equalTo: row.centerYAnchor),
    ])
    return row
  }

  static func makeOpenSourceCard(
    githubButton: NSButton,
    reportIssueButton: NSButton
  ) -> NSView {
    let icon = NSImageView()
    icon.image = NSImage(
      systemSymbolName: "chevron.left.forwardslash.chevron.right",
      accessibilityDescription: "Open Source"
    )
    icon.contentTintColor = .systemIndigo
    icon.symbolConfiguration = .init(pointSize: 17, weight: .medium)

    let iconBackground = NSView()
    iconBackground.wantsLayer = true
    iconBackground.layer?.backgroundColor =
      NSColor.systemIndigo
      .withAlphaComponent(0.12).cgColor
    iconBackground.layer?.cornerRadius = 8
    iconBackground.addSubview(icon)
    icon.translatesAutoresizingMaskIntoConstraints = false

    let title = NSTextField(labelWithString: "ViMotes on GitHub")
    title.font = .systemFont(ofSize: 13, weight: .semibold)
    let detail = NSTextField(
      wrappingLabelWithString:
        "View the source, report an issue, or support the project with a star."
    )
    detail.font = .systemFont(ofSize: 11)
    detail.textColor = .secondaryLabelColor
    detail.maximumNumberOfLines = 2
    let text = NSStackView(views: [title, detail])
    text.orientation = .vertical
    text.alignment = .leading
    text.spacing = 3

    githubButton.bezelStyle = .rounded
    githubButton.image = NSImage(
      systemSymbolName: "star",
      accessibilityDescription: "Star ViMotes on GitHub"
    )
    githubButton.imagePosition = .imageLeading
    githubButton.toolTip = "Open the ViMotes repository on GitHub"
    reportIssueButton.bezelStyle = .rounded
    reportIssueButton.toolTip = "Open a new ViMotes issue on GitHub"
    let actions = NSStackView(views: [githubButton, reportIssueButton])
    actions.orientation = .horizontal
    actions.alignment = .centerY
    actions.spacing = 8

    let row = NSStackView(views: [iconBackground, text, actions])
    row.orientation = .horizontal
    row.alignment = .centerY
    row.spacing = 12
    text.setContentHuggingPriority(.defaultLow, for: .horizontal)
    text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    actions.setContentHuggingPriority(.required, for: .horizontal)

    let card = NSBox()
    card.boxType = .custom
    card.fillColor = .controlBackgroundColor
    card.borderColor = .separatorColor
    card.borderWidth = 0.5
    card.cornerRadius = 10
    let container = NSView()
    container.addSubview(row)
    row.translatesAutoresizingMaskIntoConstraints = false
    card.contentView = container

    NSLayoutConstraint.activate([
      iconBackground.widthAnchor.constraint(equalToConstant: 36),
      iconBackground.heightAnchor.constraint(equalToConstant: 36),
      icon.centerXAnchor.constraint(equalTo: iconBackground.centerXAnchor),
      icon.centerYAnchor.constraint(equalTo: iconBackground.centerYAnchor),
      row.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
      row.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
      row.centerYAnchor.constraint(equalTo: container.centerYAnchor),
    ])
    return card
  }
}
