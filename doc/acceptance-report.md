# Implementation Acceptance Report

Date: October 8, 2026. Platform: macOS 15.8, Apple Silicon, Xcode 26.3. Deployment target: macOS 13.

## Automated Verification

- 60 Swift tests passed on arm64 and x86_64 (Intel execution through Rosetta on this machine).
- Two Python tests passed for date/commit-count versioning and shallow-history rejection.
- Production Swift code line coverage: 95.45%; region coverage: 90.57%. All core functions were exercised. Core calendar conversion line coverage is 98.29%.
- Every valid lunar day in all 200 supported lunar years (1901–2100) was round-tripped through Gregorian conversion. Invalid day/month/leap-month combinations, supported boundaries, and independent HKO conversion cases were checked.
- Gregorian leap years, second precision, time zones, nonexistent DST times, repeated DST occurrences, a half-hour transition, and a skipped civil day were tested.
- Event capacity, sorting, equal-time groups, automatic advancement, reached/empty/completed states, clock changes, restart, and resume discontinuities were tested with injected times.
- System-language selection, manual override, translation completeness, conventional lunar labels, configuration persistence, drafts/Cancel, corrupt-data preservation, explicit repair, and save failures were tested.
- Native interface tests exercise adding/deleting targets, calendar switching, leap-month controls, invalid-input correction, language switching while retaining invalid edits, Save/Cancel sheets, preference changes, and independent saver instances.
- Render comparisons verify that the entire countdown region changes position at 60 seconds, remains unchanged at 59 seconds, and stays fixed when movement is disabled or the view is a preview.

## Packaged Program Acceptance

`build.sh all` produces ad-hoc-signed arm64, x86_64, and Universal saver/preview bundles. `acceptance.sh` exercises the packaged arm64 and x86_64 executables, loads the actual saver in an independent host, checks its principal class and settings sheet, verifies start/stop/restart and independent instances, and validates architecture, signatures, and Info.plist files.

Rendered acceptance images cover English, Chinese, 320×240, portrait 450×800, a 143×80 system thumbnail, and a 500×165 settings preview. Screenshots are generated locally under `.acceptance/` and uploaded by CI rather than checked into source control.

Manual testing in the preview application verified the five-target limit, Chinese switching, calendar controls, and cancellation. The actual macOS System Settings host successfully loaded a separate temporary installation, opened its configuration sheet, saved a target, and refreshed the system preview. The existing screen saver was preserved; its original selection was restored, and the temporary installation and configuration were archived outside the user installation directory.

A remote-host accessibility issue found during acceptance was corrected by retaining the settings window's content-view identity when rebuilding translated controls; the identity is now asserted by a unit test. Tiny-preview clipping was corrected with compact labels and scaled text.

## Release Verification and Remaining Checks

The GitHub workflow tests and builds on separate ARM and native Intel runners. After a successful push to `main`, it publishes both architecture packages under `vYY.MM.DD-N`, using the commit date and reachable Git commit count. The first server run and release publication must be observed after the implementation PR is pushed/merged; configuration alone does not prove that a release has executed.

Launching the full-screen system engine activated the normal macOS lock policy. Full-screen visual operation and the 60-second movement in that host still require a manual observation after unlocking. The automated rendering/lifecycle checks do not replace that observation. Physical multi-monitor behavior, sleep/wake in the actual host, long-duration resource use, native Intel hardware, and macOS 13/14 installations have not been locally accepted.

Packages have verified ad-hoc signatures. Developer ID signing and Apple notarization are not configured, so downloaded releases may require macOS Privacy & Security approval. Calendar data is an explicit offline civil table; future lunar-boundary uncertainty is documented in [calendar-data.md](calendar-data.md).

## Settings and Packaging Follow-up

The settings panel now uses separate rounded sections for targets, date/time, live preview, and display preferences. Fields have consistent widths and aligned labels; ambiguous-time controls appear only when required. The target list uses compact, separate name/date/status rows. Gregorian equivalents appear for lunar input, and successful calendar conversion shows a green localized confirmation that survives a language switch. Empty status rows are hidden. Save/Cancel are aligned at the lower right.

Follow-up regression validation covers 61 Swift tests and three Python tests (95.80% production line coverage), including calendar-conversion confirmation in both languages, collapsing optional footer rows, opaque drawing, and exact release/bundle version and icon packaging. Release names now use `vYY.MM.DD-N` (for example, `v26.10.08-5`), without a duplicated `v` in the workflow. Both bundles include the same reproducible `.icns` icon. English and Chinese populated settings screenshots are generated by the packaged preview acceptance harness; actual preview-app interactions were also checked with temporary drafts cancelled afterward.

## Window Lifecycle, Small Displays, and Readme Follow-up

A reported preview close crash showed `EXC_BAD_ACCESS` in the main-thread timer while accessing the preview window. The preview now explicitly retains its window (`isReleasedWhenClosed = false`) and stops its timer and saver animation in `windowWillClose`, before application termination. Its application delegate is kept alive throughout the application run loop. The packaged close harness holds the event loop open for more than two timer intervals after closure and checks that the closed window remains unchanged; this check runs on both CI architectures.

Repeated `configureSheet` queries now return the same active window/draft. Save, Cancel, and an external window close stop the settings timer and invalidate the cached controller through a finish callback. Regression tests check window identity, draft retention, Cancel isolation, reopening saved data, one-time completion, and preview shutdown.

Settings use a scrollable body and a fixed bottom action bar. Initial dimensions account for the available display's visible frame; the window is resizable down to 480×320. At narrow widths the fixed-width editor remains reachable through horizontal scrolling. English and Chinese 520×420 renders and a 480×360 layout test verify that Save/Cancel stay visible while the body scrolls. Large-screen controls preserve the existing layout.

Countdown unit labels are larger, brighter, and separated from digits by an explicit gap. Compact rows reserve enough height to avoid overlap. The language-specific README screenshots are actual deterministic renders of this implementation. `README.md` is English by default, links to `README.zh-CN.md`, and both files show their respective screenshot near the top. Both README files and their screenshots are included in bundle resources.

Local regression verification for this follow-up: 63 Swift tests and three Python tests passed. Packaged ARM and Intel close/lifecycle acceptance, architecture/plist/signature checks, and screenshot rendering passed. README navigation/image/document links were checked against the repository files.

## Rendering and Settings Maintenance

Rendering now compares typed value snapshots instead of Swift reflection strings. Snapshots include the resolved display language, localized error, configuration, countdown state, preview mode, and active movement step. Fixed previews and stationary content avoid redraws caused solely by elapsed minutes. Gregorian date formatters use a bounded, locked cache keyed by locale, zone, and format, with concurrent mixed-format/zone regression coverage.

Fallback preferences polling runs once per minute. Unchanged raw data reuses its validated configuration, including a stable identity for empty settings. Changed or damaged data is still validated, and save notifications, startup, and wake refresh immediately. Tests cover polling frequency, actual distributed save notification delivery, wake handling, and an independent `/usr/bin/defaults` writer. Ordinary `UserDefaults` no longer uses explicit synchronization; macOS persists those defaults asynchronously, while immediate readback verifies the value visible to the writing instance. The later full-screen preferences follow-up below corrects the separate `ScreenSaverDefaults` behavior that this maintenance pass missed.

The settings controller's timer cleanup is owned by a separate locked timer lifetime object, whose deinitializer does not access actor-isolated UI properties. The lifetime and formatter helpers type-check in Swift 6 strict-concurrency mode; this is not a claim that the entire application has migrated to Swift 6. Timer replacement/release and the existing settings/preview closure checks cover cleanup.

The time-zone selector provides localized search and pins the selected/current/common zones without modifying drafts during search. Regression tests cover city-name search, selection changes, unmatched queries, clearing, and duplicate removal. Preview bundle names now distinguish `Countdown Preview` from `Countdown`; version dates use `Asia/Shanghai` (UTC+8). Lunar-year lookup uses supported-range/month boundaries instead of a special case for 2101; existing exhaustive and upper-boundary tests remain applicable. Saved timestamp limits are named and documented as 1901-01-01 through 9999-12-31 UTC.

Local regression verification: 74 Swift tests and three Python tests passed. See [build-and-release.md](build-and-release.md) for Intel runner lifecycle sources and migration options.

## Installed Options Recovery and Presentation Coverage

On macOS 15.8, Options initially did nothing for the installed v26.10.08-16 bundle while its preview continued to animate. No configuration-sheet exception or crash was recorded. Completely quitting System Settings and reopening its Screen Saver pane restored the settings sheet. The original installed bundle was restored byte-for-byte after temporary logging was removed; its unchanged executable was verified by SHA-256 and strict code-signature verification. Options then opened successfully. This supports a stale host/session diagnosis, rather than demonstrating a defect in configuration-window construction.

Both READMEs now explain quitting System Settings before updating and the recovery procedure. Saved configuration was preserved. The independent bundle acceptance host now attaches the saver to a real host window, presents its returned sheet, verifies visibility and parent attachment, and invokes Cancel and reopens three times. These checks run for both architectures in the existing workflow. They supplement the manual System Settings check; they do not simulate Apple's remote extension host or prove automatic recovery from every stale host session.

Local verification: all 74 Swift tests passed. Packaged arm64 and x86_64 (through Rosetta) acceptance passed, including three visible-sheet Cancel/reopen cycles per architecture, preview closure, and architecture/plist/signature checks. The unchanged installed release was also opened, cancelled, and reopened in System Settings.

## Full-Screen Preview Preferences Synchronization

A regression introduced during preferences maintenance affected actual screen saver hosts: the embedded preview used the writer's updated dictionary, while an already-running full-screen host kept its old `ScreenSaverDefaults` dictionary. Ordinary `UserDefaults` subprocess tests did not cover this subclass. An isolated two-process experiment reproduced an unchanged cached value after an external save and an updated value only after `ScreenSaverDefaults.synchronize()`.

A dedicated UI-layer backend now synchronizes the screen saver defaults before configuration reads and flushes successful writes before save notifications are posted. Failed synchronization is reported rather than claiming a successful save. Ordinary UserDefaults behavior and the decoded-configuration cache remain unchanged. Reads occur on startup/restart, save notification, wake, and the existing once-per-minute fallback, rather than synchronizing every animation frame.

Four regression tests use real ScreenSaverDefaults and independent current-host preference writers/readers: stale dictionaries and external deletion, immediate save visibility, full-size restart/fallback polling, and distributed notification delivery. Packaged preferences acceptance launches a separate copy of the actual preview executable, saves changed title/time/language through the new backend, and checks a retained full-size saver on restart and reload. Both architectures run this acceptance in the existing workflow. See Apple's [ScreenSaverDefaults](https://developer.apple.com/documentation/screensaver/screensaverdefaults) API for module-specific preferences; the need for explicit synchronization here was verified locally with the actual subclass rather than inferred from plain UserDefaults documentation.

Local verification: 78 Swift tests passed on ARM and Intel through Rosetta, with three build-version tests. Packaged ARM and Intel preferences subprocess acceptance, settings presentation/reopening, preview closure, and architecture/plist/signature checks passed.
