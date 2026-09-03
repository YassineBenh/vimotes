import Testing

@testable import ViMotesCore

struct VimEngineTests {
  @Test("Normal mode translates Vim motions without inserting text")
  func normalModeMotions() {
    var engine = VimEngine()

    #expect(engine.handle(.character("h")) == transition(.move(.characterBackward)))
    #expect(engine.handle(.character("j")) == transition(.move(.lineDown)))
    #expect(engine.handle(.character("k")) == transition(.move(.lineUp)))
    #expect(engine.handle(.character("l")) == transition(.move(.characterForward)))
    #expect(engine.handle(.character("w")) == transition(.move(.wordForward)))
    #expect(engine.handle(.character("b")) == transition(.move(.wordBackward)))
    #expect(engine.handle(.character("e")) == transition(.move(.wordEnd)))
    #expect(engine.handle(.character("0")) == transition(.move(.lineStart)))
    #expect(engine.handle(.character("_")) == transition(.move(.lineStart)))
    #expect(engine.handle(.character("$")) == transition(.move(.lineEnd)))
  }

  @Test("Insert commands enter insert mode and Escape returns to normal")
  func insertModeLifecycle() {
    var engine = VimEngine()

    #expect(
      engine.handle(.character("a"))
        == transition(
          .collapseSelection,
          .move(.characterForward),
          .changeMode(.insert),
          mode: .insert))
    #expect(engine.handle(.character("z")) == .passthrough(mode: .insert))
    #expect(
      engine.handle(.escape)
        == transition(.collapseSelection, .changeMode(.normal), mode: .normal))
  }

  @Test("Document motions support gg and G")
  func documentMotions() {
    var engine = VimEngine()

    #expect(engine.handle(.character("g")) == transition())
    #expect(engine.handle(.character("g")) == transition(.move(.documentStart)))
    #expect(engine.handle(.character("G")) == transition(.move(.documentEnd)))
  }

  @Test("Normal mode navigates paragraphs, pages, and search results")
  func extendedNavigation() {
    var engine = VimEngine()

    #expect(engine.handle(.character("{")) == transition(.move(.paragraphBackward)))
    #expect(engine.handle(.character("}")) == transition(.move(.paragraphForward)))
    #expect(engine.handle(.control("u")) == transition(.scrollHalfPage(.up)))
    #expect(engine.handle(.control("d")) == transition(.scrollHalfPage(.down)))
    #expect(engine.handle(.character("/")) == transition(.openFind))
    #expect(engine.handle(.character("n")) == transition(.findNext))
    #expect(engine.handle(.character("N")) == transition(.findPrevious))
  }

  @Test("Numeric prefixes repeat motions and atomic edits")
  func numericPrefixes() {
    var engine = VimEngine()

    #expect(engine.handle(.character("3")) == transition())
    #expect(
      engine.handle(.character("w"))
        == transition(
          .move(.wordForward),
          .move(.wordForward),
          .move(.wordForward)))
    #expect(engine.handle(.character("2")) == transition())
    #expect(
      engine.handle(.character("x"))
        == transition(
          .collapseSelection,
          .deleteForward,
          .deleteForward))
  }

  @Test("Numeric prefixes extend Visual motions")
  func visualNumericPrefixes() {
    var engine = VimEngine()
    _ = engine.handle(.character("v"))

    #expect(engine.handle(.character("2")) == transition(mode: .visual))
    #expect(
      engine.handle(.character("j"))
        == transition(
          .move(.lineDown, extendingSelection: true),
          .move(.lineDown, extendingSelection: true),
          mode: .visual))
  }

  @Test("Line operators delete, yank, or change complete lines")
  func lineOperators() {
    var engine = VimEngine()

    #expect(engine.handle(.character("d")) == transition())
    #expect(
      engine.handle(.character("d"))
        == transition(
          .collapseSelection,
          .selectCurrentLines(1),
          .deleteSelection))

    #expect(engine.handle(.character("y")) == transition())
    #expect(
      engine.handle(.character("y"))
        == transition(
          .collapseSelection,
          .selectCurrentLines(1),
          .copySelection,
          .collapseSelection))

    #expect(engine.handle(.character("c")) == transition())
    #expect(
      engine.handle(.character("c"))
        == transition(
          .collapseSelection,
          .selectCurrentLineContents(1),
          .deleteSelection,
          .changeMode(.insert),
          mode: .insert))
  }

  @Test("Operators compose with motions")
  func motionOperators() {
    var engine = VimEngine()

    #expect(engine.handle(.character("d")) == transition())
    #expect(
      engine.handle(.character("w"))
        == transition(
          .collapseSelection,
          .move(.wordForward, extendingSelection: true),
          .deleteSelection))

    #expect(engine.handle(.character("y")) == transition())
    #expect(
      engine.handle(.character("$"))
        == transition(
          .collapseSelection,
          .selectToLineBoundary(.end),
          .copySelection,
          .collapseSelection))

    #expect(engine.handle(.character("c")) == transition())
    #expect(
      engine.handle(.character("w"))
        == transition(
          .collapseSelection,
          .move(.wordEnd, extendingSelection: true),
          .deleteSelection,
          .changeMode(.insert),
          mode: .insert))
  }

  @Test("Operators compose with line and document boundaries")
  func boundaryOperators() {
    var engine = VimEngine()

    #expect(engine.handle(.character("d")) == transition())
    #expect(
      engine.handle(.character("0"))
        == transition(
          .collapseSelection,
          .selectToLineBoundary(.start),
          .deleteSelection))

    #expect(engine.handle(.character("d")) == transition())
    #expect(engine.handle(.character("g")) == transition())
    #expect(
      engine.handle(.character("g"))
        == transition(
          .collapseSelection,
          .move(.documentStart, extendingSelection: true),
          .deleteSelection))

    #expect(engine.handle(.character("y")) == transition())
    #expect(
      engine.handle(.character("G"))
        == transition(
          .collapseSelection,
          .move(.documentEnd, extendingSelection: true),
          .copySelection,
          .collapseSelection))
  }

  @Test("Operator and motion counts multiply")
  func countedOperators() {
    var engine = VimEngine()

    #expect(engine.handle(.character("5")) == transition())
    #expect(engine.handle(.character("d")) == transition())
    #expect(
      engine.handle(.character("d"))
        == transition(
          .collapseSelection,
          .selectCurrentLines(5),
          .deleteSelection))

    #expect(engine.handle(.character("2")) == transition())
    #expect(engine.handle(.character("d")) == transition())
    #expect(engine.handle(.character("3")) == transition())
    #expect(
      engine.handle(.character("w"))
        == transition(
          .collapseSelection,
          .move(.wordForward, extendingSelection: true),
          .move(.wordForward, extendingSelection: true),
          .move(.wordForward, extendingSelection: true),
          .move(.wordForward, extendingSelection: true),
          .move(.wordForward, extendingSelection: true),
          .move(.wordForward, extendingSelection: true),
          .deleteSelection))
  }

  @Test("Replace accepts one character and honors a count")
  func replaceCharacters() {
    var engine = VimEngine()

    #expect(engine.handle(.character("r")) == transition())
    #expect(
      engine.handle(.character("é"))
        == transition(
          .collapseSelection,
          .deleteForward,
          .insertText("é")))

    #expect(engine.handle(.character("3")) == transition())
    #expect(engine.handle(.character("r")) == transition())
    #expect(
      engine.handle(.character("x"))
        == transition(
          .collapseSelection,
          .deleteForward,
          .insertText("x"),
          .deleteForward,
          .insertText("x"),
          .deleteForward,
          .insertText("x")))
  }

  @Test("Dot repeats the last complete Normal-mode change")
  func repeatLastChange() {
    var engine = VimEngine()

    #expect(
      engine.handle(.character("x"))
        == transition(.collapseSelection, .deleteForward))
    #expect(
      engine.handle(.character("."))
        == transition(.collapseSelection, .deleteForward))

    #expect(engine.handle(.character("r")) == transition())
    #expect(
      engine.handle(.character("z"))
        == transition(
          .collapseSelection,
          .deleteForward,
          .insertText("z")))
    #expect(engine.handle(.character("2")) == transition())
    #expect(
      engine.handle(.character("."))
        == transition(
          .collapseSelection,
          .deleteForward,
          .insertText("z"),
          .collapseSelection,
          .deleteForward,
          .insertText("z")))
  }

  @Test("Dot repeats text typed by Insert and change commands")
  func repeatInsertedText() {
    var engine = VimEngine()

    #expect(
      engine.handle(.character("i"))
        == transition(
          .collapseSelection,
          .changeMode(.insert),
          mode: .insert))
    #expect(engine.handle(.character("a")) == .passthrough(mode: .insert))
    #expect(engine.handle(.character("b")) == .passthrough(mode: .insert))
    #expect(
      engine.handle(.escape)
        == transition(.collapseSelection, .changeMode(.normal), mode: .normal))
    #expect(
      engine.handle(.character("."))
        == transition(.collapseSelection, .insertText("ab")))

    #expect(engine.handle(.character("c")) == transition())
    #expect(
      engine.handle(.character("c"))
        == transition(
          .collapseSelection,
          .selectCurrentLineContents(1),
          .deleteSelection,
          .changeMode(.insert),
          mode: .insert))
    #expect(engine.handle(.character("z")) == .passthrough(mode: .insert))
    _ = engine.handle(.escape)
    #expect(
      engine.handle(.character("."))
        == transition(
          .collapseSelection,
          .selectCurrentLineContents(1),
          .deleteSelection,
          .insertText("z")))
  }

  @Test("Yanks do not replace the last repeatable change")
  func yankPreservesLastChange() {
    var engine = VimEngine()
    _ = engine.handle(.character("x"))
    _ = engine.handle(.character("y"))
    _ = engine.handle(.character("y"))

    #expect(
      engine.handle(.character("."))
        == transition(.collapseSelection, .deleteForward))
  }

  @Test("Invalid pending commands pass through and clear their state")
  func invalidPendingCommands() {
    var engine = VimEngine()

    #expect(engine.handle(.character("d")) == transition())
    #expect(engine.handle(.character("q")) == passthrough(.insertText("d")))
    #expect(engine.handle(.character("d")) == transition())
    #expect(
      engine.handle(.character("d"))
        == transition(
          .collapseSelection,
          .selectCurrentLines(1),
          .deleteSelection))

    #expect(engine.handle(.character("r")) == transition())
    #expect(engine.handle(.other) == passthrough(.insertText("r")))
    #expect(engine.handle(.character("r")) == transition())
    #expect(
      engine.handle(.character("x"))
        == transition(
          .collapseSelection,
          .deleteForward,
          .insertText("x")))

    #expect(engine.handle(.character("2")) == transition())
    #expect(engine.handle(.character("q")) == passthrough(.insertText("2")))
  }

  @Test("Counts apply to line yank and delete shortcuts")
  func countedLineShortcuts() {
    var engine = VimEngine()

    #expect(engine.handle(.character("3")) == transition())
    #expect(
      engine.handle(.character("Y"))
        == transition(
          .collapseSelection,
          .selectCurrentLines(3),
          .copySelection,
          .collapseSelection))

    #expect(engine.handle(.character("2")) == transition())
    #expect(
      engine.handle(.character("D"))
        == transition(
          .collapseSelection,
          .selectCurrentLines(2),
          .deleteSelection))
  }

  @Test("Editing commands produce native-safe actions")
  func editingCommands() {
    var engine = VimEngine()

    #expect(engine.handle(.character("x")) == transition(.collapseSelection, .deleteForward))
    #expect(engine.handle(.character("u")) == transition(.undo))
    #expect(engine.handle(.control("r")) == transition(.redo))
    #expect(
      engine.handle(.character("A"))
        == transition(.move(.lineEnd), .changeMode(.insert), mode: .insert))
  }

  @Test("Normal mode supports complementary editing commands")
  func complementaryEditingCommands() {
    var engine = VimEngine()

    #expect(
      engine.handle(.character("X"))
        == transition(.collapseSelection, .deleteBackward))
    #expect(
      engine.handle(.character("p"))
        == transition(.collapseSelection, .move(.characterForward), .paste))
    #expect(
      engine.handle(.character("P"))
        == transition(.collapseSelection, .paste))
    #expect(
      engine.handle(.character("J"))
        == transition(
          .collapseSelection,
          .joinLines(1)))
    #expect(
      engine.handle(.character("C"))
        == transition(
          .collapseSelection,
          .selectToLineBoundary(.end),
          .deleteSelection,
          .changeMode(.insert),
          mode: .insert))

    engine = VimEngine()
    #expect(
      engine.handle(.character("S"))
        == transition(
          .collapseSelection,
          .selectCurrentLineContents(1),
          .deleteSelection,
          .changeMode(.insert),
          mode: .insert))
  }

  @Test("Visual mode extends motions and can delete the selection")
  func visualMode() {
    var engine = VimEngine()

    #expect(
      engine.handle(.character("v"))
        == transition(
          .collapseSelection,
          .selectCurrentCharacter,
          .changeMode(.visual),
          mode: .visual))
    #expect(
      engine.handle(.character("w"))
        == transition(.move(.wordForward, extendingSelection: true), mode: .visual))
    #expect(
      engine.handle(.character("e"))
        == transition(.move(.wordEnd, extendingSelection: true), mode: .visual))
    #expect(
      engine.handle(.character("_"))
        == transition(.move(.lineStart, extendingSelection: true), mode: .visual))
    #expect(
      engine.handle(.character("d"))
        == transition(.deleteSelection, .changeMode(.normal), mode: .normal))
  }

  @Test("Shift-V selects the current line and enters Visual mode")
  func visualLineMode() {
    var engine = VimEngine()

    #expect(
      engine.handle(.character("V"))
        == transition(
          .collapseSelection,
          .selectCurrentLines(1),
          .changeMode(.visual),
          mode: .visual))
  }

  @Test("Shift-Y yanks the current line and stays in Normal mode")
  func yankCurrentLine() {
    var engine = VimEngine()

    #expect(
      engine.handle(.character("Y"))
        == transition(
          .collapseSelection,
          .selectCurrentLines(1),
          .copySelection,
          .collapseSelection))
  }

  @Test("Shift-D deletes the current line and stays in Normal mode")
  func deleteCurrentLine() {
    var engine = VimEngine()

    #expect(
      engine.handle(.character("D"))
        == transition(
          .collapseSelection,
          .selectCurrentLines(1),
          .deleteSelection))
  }

  @Test("Visual mode supports gg and clears selection when cancelled")
  func visualDocumentStartAndCancel() {
    var engine = VimEngine()
    _ = engine.handle(.character("v"))

    #expect(engine.handle(.character("g")) == transition(mode: .visual))
    #expect(
      engine.handle(.character("g"))
        == transition(.move(.documentStart, extendingSelection: true), mode: .visual))
    #expect(
      engine.handle(.escape)
        == transition(.collapseSelection, .changeMode(.normal), mode: .normal))
  }

  @Test("Visual yank copies the selection and returns to normal mode")
  func visualYank() {
    var engine = VimEngine()
    _ = engine.handle(.character("v"))
    _ = engine.handle(.character("w"))

    #expect(
      engine.handle(.character("y"))
        == transition(
          .copySelection,
          .collapseSelection,
          .changeMode(.normal),
          mode: .normal))
  }

  @Test("Unmapped input passes through without changing mode")
  func unmappedInput() {
    var engine = VimEngine()

    #expect(engine.handle(.character("q")) == .passthrough(mode: .normal))
    #expect(engine.handle(.control("x")) == .passthrough(mode: .normal))
    #expect(engine.handle(.other) == .passthrough(mode: .normal))
    #expect(engine.handle(.escape) == transition(.collapseSelection))
    #expect(engine.handle(.command("c")) == .passthrough(mode: .normal))

    _ = engine.handle(.character("v"))
    #expect(engine.handle(.character("q")) == .passthrough(mode: .visual))
    #expect(engine.handle(.control("x")) == .passthrough(mode: .visual))
    #expect(engine.mode == .visual)
  }

  @Test("Unmapped input clears an incomplete command prefix")
  func unmappedInputClearsPrefix() {
    var engine = VimEngine()

    #expect(engine.handle(.character("g")) == transition())
    #expect(engine.handle(.character("q")) == passthrough(.insertText("g")))
    #expect(engine.handle(.character("g")) == transition())
    #expect(engine.handle(.character("g")) == transition(.move(.documentStart)))
  }

  private func transition(
    _ actions: VimAction...,
    mode: VimMode = .normal
  ) -> VimTransition {
    VimTransition(consumesInput: true, actions: actions, mode: mode)
  }

  private func passthrough(
    _ actions: VimAction...,
    mode: VimMode = .normal
  ) -> VimTransition {
    VimTransition(consumesInput: false, actions: actions, mode: mode)
  }
}
