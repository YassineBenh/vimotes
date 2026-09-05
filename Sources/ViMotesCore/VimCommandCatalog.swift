public enum VimCommandCatalog {
  public static let motionKeys = "h j k l · w b e · 0 _ $ · { } · gg G"

  public static func motion(for character: Character) -> CursorMotion? {
    switch character {
    case "h": .characterBackward
    case "j": .lineDown
    case "k": .lineUp
    case "l": .characterForward
    case "w": .wordForward
    case "b": .wordBackward
    case "e": .wordEnd
    case "0", "_": .lineStart
    case "$": .lineEnd
    case "G": .documentEnd
    case "{": .paragraphBackward
    case "}": .paragraphForward
    default: nil
    }
  }
}
