import Testing

@testable import ViMotesCore

struct VimSafetyTests {
  @Test func nativeVisualEditsInvalidateTheSelectionRecording() {
    var engine = VimEngine()
    for key in "xv" { _ = engine.handle(.character(key)) }
    _ = engine.handle(.command("v"))
    _ = engine.handle(.character("d"))
    #expect(engine.handle(.character(".")).actions.isEmpty)
  }

  @Test func visualDeletionReplaysTheSelection() {
    var engine = VimEngine()
    for key in "xvlld" { _ = engine.handle(.character(key)) }
    #expect(
      engine.handle(.character(".")).actions == [
        .collapseSelection, .selectCurrentCharacter,
        .move(.characterForward, extendingSelection: true),
        .move(.characterForward, extendingSelection: true), .deleteSelection,
      ])
  }

  @Test func backspaceBeyondInsertionInvalidatesRepeat() {
    var engine = VimEngine()
    for key in "xia" { _ = engine.handle(.character(key)) }
    _ = engine.handle(.backspace)
    _ = engine.handle(.backspace)
    _ = engine.handle(.escape)
    #expect(engine.handle(.character(".")).actions.isEmpty)
  }

  @Test func newlinesAndTabsAreRecordedAsText() {
    var engine = VimEngine()
    _ = engine.handle(.character("i"))
    _ = engine.handle(.character("a"))
    _ = engine.handle(.newline)
    _ = engine.handle(.tab)
    _ = engine.handle(.character("b"))
    _ = engine.handle(.escape)
    #expect(engine.handle(.character(".")).actions == [.collapseSelection, .insertText("a\n\tb")])
  }

  @Test func focusLossInvalidatesUnfinishedInsertion() {
    var engine = VimEngine()
    for key in "xcchello" { _ = engine.handle(.character(key)) }
    engine.cancelContext()
    #expect(engine.mode == .normal)
    #expect(engine.handle(.character(".")).actions.isEmpty)
  }

  @Test func recordingIsBoundedInBytes() {
    var engine = VimEngine()
    _ = engine.handle(.character("i"))
    for _ in 0...VimEngine.maximumRecordedTextBytes / 4 {
      _ = engine.handle(.character("😀"))
    }
    _ = engine.handle(.escape)
    #expect(engine.handle(.character(".")).actions.isEmpty)
  }

  @Test func everyMotionUsesTheSameCatalog() {
    for key in "hjklwbe0_$G{}" {
      var normal = VimEngine()
      var visual = VimEngine()
      _ = visual.handle(.character("v"))
      let motion = VimCommandCatalog.motion(for: key)!
      #expect(normal.handle(.character(key)).actions == [.move(motion)])
      #expect(visual.handle(.character(key)).actions == [.move(motion, extendingSelection: true)])
    }
  }

  @Test func visualChangeReplacesPreviousChange() {
    var engine = VimEngine()
    for key in "xvlcZ" { _ = engine.handle(.character(key)) }
    _ = engine.handle(.escape)
    let actions = engine.handle(.character(".")).actions
    #expect(actions.contains(.deleteSelection))
    #expect(actions.contains(.insertText("Z")))
    #expect(!actions.contains(.deleteForward))
  }

  @Test func backspaceEditsOnlyRecordedInsertion() {
    var engine = VimEngine()
    for key in "iab" { _ = engine.handle(.character(key)) }
    _ = engine.handle(.backspace)
    _ = engine.handle(.character("c"))
    _ = engine.handle(.escape)
    #expect(engine.handle(.character(".")).actions == [.collapseSelection, .insertText("ac")])
  }

  @Test func interruptedInsertionCannotReplayAnOldDelete() {
    var engine = VimEngine()
    for key in "xcc" { _ = engine.handle(.character(key)) }
    _ = engine.handle(.other)
    _ = engine.handle(.escape)
    #expect(engine.handle(.character(".")).actions.isEmpty)
  }

  @Test func contextCancellationDropsPendingOperator() {
    var engine = VimEngine()
    _ = engine.handle(.character("d"))
    engine.cancelContext()
    #expect(engine.handle(.character("w")).actions == [.move(.wordForward)])
  }

  @Test func repetitionHasAFixedWorkBudget() {
    var engine = VimEngine()
    for key in "999x999" { _ = engine.handle(.character(key)) }
    #expect(engine.handle(.character(".")).actions.isEmpty)
    #expect(engine.handle(.character("x")).actions.count <= VimEngine.maximumActions)
  }

  @Test func controlCharactersAreNeverRecordedAsText() {
    var engine = VimEngine()
    for key in "iab" { _ = engine.handle(.character(key)) }
    _ = engine.handle(.character("\u{7f}"))
    _ = engine.handle(.escape)
    #expect(engine.handle(.character(".")).actions.isEmpty)
  }
}
