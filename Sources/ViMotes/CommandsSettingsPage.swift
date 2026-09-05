import AppKit
import ViMotesCore

extension SettingsViews {
  static func makeCommandsView() -> NSView {
    let normal = makeCommandRow(
      mode: "NORMAL",
      commands: VimCommandCatalog.motionKeys,
      detail: "Characters, lines, words, paragraphs, and document boundaries",
      color: .systemBlue
    )
    let insert = makeCommandRow(
      mode: "INSERT",
      commands: "i a I A   o O   Esc",
      detail: "Enter Insert mode at the cursor, line boundaries, or a new line",
      color: .systemGreen
    )
    let editing = makeCommandRow(
      mode: "OPERATE",
      commands: "dd yy cc · d c y + motion",
      detail: "Delete, change, or yank lines and motion-defined ranges",
      color: .systemPurple
    )
    let changes = makeCommandRow(
      mode: "EDIT",
      commands: "x X · C S D Y J · r{char} · p P",
      detail: "Delete, change, replace, join, yank, and paste",
      color: .systemPink
    )
    let navigation = makeCommandRow(
      mode: "MORE",
      commands: "[count] · u Ctrl-r · . · / n N · Ctrl-u/d",
      detail: "Repeat, undo, search, and scroll by half a page",
      color: .systemIndigo
    )
    let visual = makeCommandRow(
      mode: "VISUAL",
      commands: "v V   motions   d x c y   Esc",
      detail: "Select characters or lines, then delete, change, yank, or cancel",
      color: .systemOrange
    )
    let rows = NSStackView(views: [
      normal,
      makeDivider(),
      insert,
      makeDivider(),
      editing,
      makeDivider(),
      changes,
      makeDivider(),
      navigation,
      makeDivider(),
      visual,
    ])
    rows.orientation = .vertical
    rows.alignment = .width
    rows.spacing = 0

    return makePage(
      title: "Supported commands",
      detail: "Commands currently translated into native Apple Notes actions.",
      symbol: "keyboard",
      color: .systemIndigo,
      content: rows,
      constraints: [
        normal.heightAnchor.constraint(equalToConstant: 48),
        insert.heightAnchor.constraint(equalToConstant: 48),
        editing.heightAnchor.constraint(equalToConstant: 48),
        changes.heightAnchor.constraint(equalToConstant: 48),
        navigation.heightAnchor.constraint(equalToConstant: 48),
        visual.heightAnchor.constraint(equalToConstant: 48),
      ]
    )
  }

  static func makeCommandRow(
    mode: String,
    commands: String,
    detail: String,
    color: NSColor
  ) -> NSView {
    let dot = NSView()
    dot.wantsLayer = true
    dot.layer?.backgroundColor = color.cgColor
    dot.layer?.cornerRadius = 4
    let modeField = NSTextField(labelWithString: mode)
    modeField.font = .monospacedSystemFont(ofSize: 10.5, weight: .semibold)
    modeField.textColor = color
    let modeStack = NSStackView(views: [dot, modeField])
    modeStack.orientation = .horizontal
    modeStack.alignment = .centerY
    modeStack.spacing = 7

    let commandsField = NSTextField(labelWithString: commands)
    commandsField.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
    let detailField = NSTextField(labelWithString: detail)
    detailField.font = .systemFont(ofSize: 10.5)
    detailField.textColor = .secondaryLabelColor
    let text = NSStackView(views: [commandsField, detailField])
    text.orientation = .vertical
    text.alignment = .leading
    text.spacing = 4
    let row = NSView()
    row.addSubview(modeStack)
    row.addSubview(text)
    modeStack.translatesAutoresizingMaskIntoConstraints = false
    text.translatesAutoresizingMaskIntoConstraints = false
    text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    NSLayoutConstraint.activate([
      dot.widthAnchor.constraint(equalToConstant: 8),
      dot.heightAnchor.constraint(equalToConstant: 8),
      modeStack.leadingAnchor.constraint(equalTo: row.leadingAnchor),
      modeStack.centerYAnchor.constraint(equalTo: row.centerYAnchor),
      modeStack.widthAnchor.constraint(equalToConstant: 112),
      text.leadingAnchor.constraint(equalTo: modeStack.trailingAnchor, constant: 20),
      text.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor),
      text.centerYAnchor.constraint(equalTo: row.centerYAnchor),
    ])
    return row
  }
}
