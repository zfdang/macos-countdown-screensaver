# Implementation Acceptance Report

Date: October 8, 2026. Platform: macOS 15.8, Apple Silicon, Xcode 26.3. Deployment target: macOS 13.

## Automated Verification

- 60 Swift tests passed on arm64 and x86_64 (Intel execution through Rosetta on this machine).
- Two Python tests passed for date/commit-count versioning and shallow-history rejection.
- Production Swift code line coverage: 95.45%; region coverage: 90.57%. All core functions were exercised. Core calendar conversion line coverage is 98.29%.
- Every valid lunar day in all 200 supported lunar years (1901–2100) was round-tripped through Gregorian conversion. Invalid day/month/leap-month combinations, supported boundaries, and independent HKO/reference fixtures were checked.
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
