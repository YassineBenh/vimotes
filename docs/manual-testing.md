# Manual regression checks

Use a disposable Apple Notes note with several short lines. Do not use personal notes
for deletion tests. Quit any other ViMotes instance before launching the test bundle.
Check Accessibility permission for that exact build; an ad hoc signature may require
granting permission again.

These checks complement `swift test`. The fake editor tests verify sequencing and
cancellation but cannot prove how a particular Apple Notes version handles native events.

## Editing and cancellation

1. In Normal mode, navigate with `h`, `j`, `k`, `l`, `w`, `b`, `gg`, and `G`.
   Only the cursor should move. Verify Insert typing still works normally.
2. At the end of the document with no selection, run `dl` and `dw`.
   Neither command should delete the character before the cursor.
3. Type `d`, switch to another note or app, return, then type `w`.
   `w` must move the cursor rather than completing the old delete command.
   Repeat after clicking in the note and disabling/re-enabling ViMotes.
4. On a populated line, type `cc`, replacement text, and Escape quickly.
   The replacement text must be preserved in order. Repeat with `o` and `O`.
5. Type `i`, `ab`, Backspace, `c`, Escape, then `.`.
   The repeated insertion must be `ac`, not a control character or the original `abc`.
6. Make an `x` edit, enter Insert, move the cursor with an arrow key, then Escape and `.`.
   Dot must not replay the older deletion. Repeat with a native paste during insertion.
7. Make an `x` edit, select with `vll`, change with `c`, type replacement text, then Escape.
   Dot must repeat the Visual change, not the earlier `x`. Also test `Vd` and `vy`.
8. Try `999x999.` in a long disposable note. Counts must remain bounded and the oversized
   dot repeat must be ignored. Escape during a long Normal-mode command or changing focus
   must stop pending work. No edits may spill into another app or note.
9. Verify `yy`/`p`, `dd`, `cc`, `J`, Undo, and Redo on plain text, lists, and checklists.
   Copy feedback should only appear when a non-empty selection was actually copied.

## Interface and updates

1. Open all three Settings tabs. Check layout, switches, links, and permission status.
2. Move and resize Notes, then switch apps. Indicators should follow or disappear without
   flashing. Yank feedback should return to the current mode after the brief pulse.
3. With a signed test build and a separate reachable test appcast, check manually for an
   update. There must be no option for silent automatic installation.
4. Let Sparkle find a scheduled update in the background. Confirm the menu bar indicates
   availability without stealing focus, opens the update, and clears the indicator after
   the update is attended to or dismissed.
5. Run the full old-build → new-build update on test copies and repeat the editing checks.
   A private or unpublished production appcast can return an update-check error; that is
   not a successful validation of the update flow.

Do not publish a candidate until the relevant checks pass on its signed/notarized bundle.
