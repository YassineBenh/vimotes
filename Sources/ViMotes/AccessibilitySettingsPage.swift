import AppKit

extension SettingsViews {
  static func makeAccessibilityView(
    statusDot: NSView,
    statusTitle: NSTextField,
    statusDetail: NSTextField,
    actionButton: NSButton
  ) -> NSView {
    statusDot.wantsLayer = true
    statusDot.layer?.cornerRadius = 5
    statusTitle.font = .systemFont(ofSize: 14, weight: .semibold)
    statusDetail.font = .systemFont(ofSize: 11.5)
    statusDetail.textColor = .secondaryLabelColor
    statusDetail.maximumNumberOfLines = 2
    actionButton.bezelStyle = .rounded

    let statusText = NSStackView(views: [statusTitle, statusDetail])
    statusText.orientation = .vertical
    statusText.alignment = .leading
    statusText.spacing = 4
    let statusRow = NSStackView(views: [statusDot, statusText, actionButton])
    statusRow.orientation = .horizontal
    statusRow.alignment = .centerY
    statusRow.spacing = 12
    statusText.setContentHuggingPriority(.defaultLow, for: .horizontal)
    statusText.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    actionButton.setContentHuggingPriority(.required, for: .horizontal)

    let statusCard = NSBox()
    statusCard.boxType = .custom
    statusCard.fillColor = .controlBackgroundColor
    statusCard.borderColor = .separatorColor
    statusCard.borderWidth = 0.5
    statusCard.cornerRadius = 10
    let statusContainer = NSView()
    statusContainer.addSubview(statusRow)
    statusRow.translatesAutoresizingMaskIntoConstraints = false
    statusCard.contentView = statusContainer
    NSLayoutConstraint.activate([
      statusRow.leadingAnchor.constraint(equalTo: statusContainer.leadingAnchor, constant: 16),
      statusRow.trailingAnchor.constraint(equalTo: statusContainer.trailingAnchor, constant: -16),
      statusRow.centerYAnchor.constraint(equalTo: statusContainer.centerYAnchor),
    ])

    let privacyTitle = NSTextField(labelWithString: "What ViMotes can access")
    privacyTitle.font = .systemFont(ofSize: 13, weight: .semibold)
    let privacyDetail = NSTextField(
      wrappingLabelWithString:
        "Accessibility is used to identify the focused Apple Notes editor and intercept keyboard input while it is active. ViMotes reads selection metadata, not note text, and edits through native keyboard events."
    )
    privacyDetail.font = .systemFont(ofSize: 11.5)
    privacyDetail.textColor = .secondaryLabelColor
    privacyDetail.maximumNumberOfLines = 3
    let privacy = NSStackView(views: [privacyTitle, privacyDetail])
    privacy.orientation = .vertical
    privacy.alignment = .leading
    privacy.spacing = 6

    let content = NSStackView(views: [statusCard, privacy])
    content.orientation = .vertical
    content.alignment = .width
    content.spacing = 22

    return makePage(
      title: "Accessibility",
      detail: "Check the permission required for ViMotes to work in Apple Notes.",
      symbol: "lock.shield",
      color: .systemGreen,
      content: content,
      constraints: [
        statusCard.heightAnchor.constraint(equalToConstant: 88),
        statusDot.widthAnchor.constraint(equalToConstant: 10),
        statusDot.heightAnchor.constraint(equalToConstant: 10),
      ]
    )
  }
}
