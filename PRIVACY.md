# Privacy

ViMotes contains no analytics, telemetry, advertising, or crash-reporting service. It
does not transmit Apple Notes content.

## Accessibility and Keyboard Events

ViMotes uses macOS Accessibility permission and a session keyboard event tap. It checks
that an editable Apple Notes area is focused before interpreting a keystroke. Keyboard
events received while another app or a non-editable Notes area is focused pass through
unchanged and are not recorded.

Through Accessibility, ViMotes reads the focused element's role and enabled state,
window geometry, selection ranges, line indexes, and character count. It does not
request the note text or selected text.

## In-Memory Repeat Data

To support the Vim `.` command, ViMotes keeps the last repeatable change in process
memory. When that change includes text typed directly in Insert mode, the text remains
in memory until another repeatable change replaces it, an unsupported edit or interrupted
insertion invalidates it, or ViMotes exits. Recorded Insert text is limited to 16 KiB.
ViMotes does not
explicitly write this text to disk or transmit it. Invoking `.` inserts it into Notes
again.

## Clipboard

Yank commands send the standard macOS Copy shortcut, which places the selected text on
the system clipboard. Paste commands send the standard Paste shortcut. ViMotes does not
directly read or persist clipboard contents.

## Local Preferences

ViMotes stores mode-indicator and automatic-update preferences in macOS user defaults.
Launch at login is managed by macOS. These settings contain no note text.

## Updates

Signed release builds use Sparkle to request
`https://yassinebenh.github.io/vimotes/appcast.xml` when checking for updates. The
request identifies the installed ViMotes version and macOS version so Sparkle can select
a compatible update. Sparkle system profiling is disabled, and updates are never
installed silently: automatic installation is disabled in the app configuration and
each installation requires user approval. Available updates are indicated in the menu bar.

GitHub serves the appcast and release downloads over HTTPS and receives normal request
metadata, including the connecting IP address. Downloaded updates are checked using
Sparkle signatures. Automatic checks can be disabled in General settings; manual checks
remain available.

Builds compiled from source do not check for updates unless a valid Sparkle public key
is configured in the application bundle.

## Support

Bug reports and support requests are handled through
[GitHub Issues](https://github.com/YassineBenh/vimotes/issues). Issues and their comments
are visible to anyone when the repository is public; authors cannot make individual
issues private. Do not include credentials, private note contents, or other sensitive
information in reports, screenshots, or attachments. Information submitted to GitHub
is also governed by GitHub's privacy policy.
