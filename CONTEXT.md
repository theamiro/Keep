# Keep

Keep is an in-app diagnostics tool for iOS internal builds. It captures what the app logs and what it sends over the network, so a tester can share a report of what went wrong.

## Language

### Builds and people

**Internal build**:
An app build made for a non-production environment and given to developers and testers. It is the only kind of build that contains Keep.
_Avoid_: debug build, test build, staging build

**Production build**:
An app build distributed to customers. It never contains Keep, whatever its build configuration is called.
_Avoid_: release build (a "Release" configuration can still be an internal build)

**Tester**:
A person running an internal build who reports problems by sharing reports.
_Avoid_: user, customer

### Capture

**Log entry**:
A single message the app wrote through swift-log, captured by Keep together with its level, label and metadata.
_Avoid_: log, event, line

**Network transaction**:
A single HTTP request and its response (or error), captured by Keep with timing, headers and bodies.
_Avoid_: call, request, API log

**Session**:
All log entries and network transactions captured during one run of the app process. A session ends when the process ends.
_Avoid_: launch, run, log file

**Redaction**:
Replacing the sensitive parts of a log entry or network transaction before Keep holds on to it. In Keep, redaction is always on.
_Avoid_: masking, sanitizing, scrubbing

**Allow-listed key**:
A metadata or header key the app declares safe, so redaction leaves its value untouched.
_Avoid_: whitelist, exemption

### Access and sharing

**Shake menu**:
The menu a tester opens by shaking the device anywhere in an internal build. It lists the available tools.
_Avoid_: debug menu, dev menu

**Tool**:
An entry in the shake menu that opens a diagnostic screen. Keep supplies the log viewer, and the app can register its own tools (for example, Design system).
_Avoid_: plugin, module, debug screen

**Log viewer**:
Keep's tool for browsing, filtering and sharing the current session's log entries and network transactions.
_Avoid_: debug log, console, FileLogViewController

**Report**:
A shareable archive of a session, together with device and app context and an optional note, that the tester sends through the system share sheet to a destination of their choice.
_Avoid_: export, dump, log file

**Sharing mode**:
The app's choice of what testers may send through the share sheet: anything, encrypted files only, or nothing. Copying to the clipboard is allowed in every mode.
_Avoid_: share policy, export setting

**Encrypted file**:
A report or detail file locked with a password the tester chooses when sharing. Whoever receives it needs that password, passed on separately, to open it.
_Avoid_: protected report, secure export

**Note**:
The tester's own free-text description of what went wrong, included in a report.
_Avoid_: comment, description
