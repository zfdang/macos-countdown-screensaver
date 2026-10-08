# macOS Multi-Event Countdown Screen Saver Design Proposal

Version: v1.1 draft

Date: 2026-10-08

Reference project: `/Users/zfdang/workspaces/Countdown`

Scope: Product behavior, UI, date rules, architecture, and acceptance criteria. Application implementation is outside this documentation phase.

## 1. Product Overview

Build a native macOS `.saver` that retains the reference application's black background, thin large digits, and four countdown columns. Users configure up to five events, each with a Gregorian or Chinese lunar date and an exact time down to seconds.

Resolve all events to absolute timestamps and sort them chronologically. Display the nearest future event and advance automatically when it expires. Ordering means the order of event timestamps, rather than entry order or a rotating slideshow.

| Setting | Proposed behavior |
| --- | --- |
| Event count | 0–5, including expired events that have not been deleted |
| Event type | One-time Gregorian or Chinese lunar date and time |
| Display order | Ascending absolute timestamp |
| Expiration | Brief completion message, then advance to the next event |
| All events expired | Display a completion state without repeating events |
| Identical timestamps | Allowed; treat simultaneous events as one group |
| Time zone | Initially the system time zone at configuration time; persist it explicitly and allow manual selection |
| UI language | Default to System: Chinese for a Chinese system language, English for every other language; allow manual Chinese or English selection |
| Lunar year range | Proposed range: 1901–2100; confirm through conversion tests before claiming support |

Lunar support means the Chinese lunar calendar. Annual repetition, automatic birthday renewal, and holiday generation are future features requiring separate recurrence rules.

Project design documents are written in English. The README is bilingual, with equivalent English and Chinese sections. The application provides separate English and Chinese interfaces rather than showing both languages together.

## 2. Reference Application Review

Reviewed the reference README, `CountdownView.swift`, `PlaceView.swift`, `Preferences.swift`, the configuration controller and XIB, and `countdown.gif`.

### 2.1 Design to Retain

- Black background, white countdown digits, and subdued unit labels.
- Four centered columns: days, hours, minutes, and seconds.
- Monospaced digits to avoid width changes during updates.
- Configuration through the native screen saver options sheet.
- A standalone preview application for development and visual verification.

### 2.2 Required Changes

The reference stores one timestamp and displays elapsed time for past dates using absolute component values. The new version needs an event list, lunar input, automatic advancement, and a completion state.

- Replace `Calendar.current` component differences with absolute elapsed seconds. Define a countdown day as exactly 24 hours to avoid DST ambiguity.
- Replace approximately 30 updates per second for static digits with once-per-second updates and redraw only when needed.
- Support configuration changes across processes; process-local notifications alone are insufficient.
- Do not copy the reference's `exit(0)` stop handling into the system host. Manage view lifecycle correctly and verify compatibility in the actual host.
- Reset stopped state and reload configuration on every start.

Retain existing MIT copyright and license notices if reference code is reused.

## 3. Screen Design

### 3.1 Main View

```text
                         Countdown to Project Launch

                      019       02       49       23
                     DAYS     HOURS   MINUTES   SECONDS

                     Jan 1, 2027, 09:00:00 · Asia/Shanghai
                                 Event 1 / 3

                     Next: Lunar New Year Reunion · [date]
```

The mockup illustrates layout only; the numbers are not a calculated example. All application-owned labels use the selected UI language.

- Background: `#000000`; primary digits: `#F5F5F5`; title: approximately 80% white; supporting labels: approximately 50% white.
- Use the system font with light/thin weight and monospaced digits; do not bundle fonts.
- Days have at least two digits and expand without truncation; hours, minutes, and seconds always have two digits.
- Place the title above the main digits, with date and event position below.
- Show the title, date, and position by default. The next-event hint is optional and off by default.
- For lunar events, show the original lunar date, corresponding Gregorian date, and event time zone.
- Allow up to two title lines and propose a 40-character title limit. Blank titles use a localized generated label such as “Event 1”; user-entered titles are preserved verbatim.
- Scale fonts for available width, height, and day-digit count. In small previews, reduce spacing, hide the next-event hint, and use a 2×2 layout if necessary.

Position uses the complete sorted configuration: after the first event expires, show “Event 2 / 5”. Generate the next-event hint from the same sorted snapshot.

### 3.2 Display States

| State | Content and behavior |
| --- | --- |
| No events | Prompt the user to add an event in screen saver options |
| Counting down | Current event and four remaining-time columns |
| Normal expiration | Zero digits and a localized event-reached message for up to two seconds |
| All events expired | Localized completion message, with the most recent event's title and date |
| Configuration unreadable | Brief setup prompt; preserve data and explain the error in settings |

Show expiration messages only when continuous screen saver operation normally crosses an event timestamp. On startup, wake, a large clock adjustment, or a configuration update, select the current future event directly without replaying historical completions.

An expiration message lasts at most two seconds. If the next event expires during that interval, immediately handle the new expiration so that the previous message does not block it. No sound, system notification, or interaction is required.

### 3.3 Multiple Displays and Movement

Each display adapts its own layout while showing the same event. Use the same time source and configuration rather than a mutable global current-event index.

To reduce prolonged fixed placement, move the content block slightly every 60 seconds within safe bounds. Cap displacement at approximately 2% of the view size and retain edge margins. Enable the localized “Move content slowly” option by default. Keep preview positioning fixed for layout inspection.

## 4. Configuration Interface

### 4.1 Window Layout

Use a native configuration sheet, initially around 820×560 pt, adapted to smaller screens. Place the event list on the left, the selected-event editor and small preview on the right, and general preferences plus Cancel/Save below.

```text
+------------------------ Countdown Settings ------------------------+
| Events (3 / 5)           | Name: [Project Launch                  ] |
| 1. Project Launch        | Calendar: [Gregorian] [Chinese Lunar]   |
|    [date] · Upcoming     | Date: [year] [month] [day]              |
| 2. New Year Reunion      | Time: [09] : [00] : [00]                |
|    [date] · Upcoming     | Time zone: [Asia/Shanghai            v] |
| 3. Departure             | Gregorian equivalent: [date and time]  |
|    [date] · Upcoming     |                                         |
| [+ Add] [- Delete]       | [Countdown preview]                     |
+-------------------------+-----------------------------------------+
| Language: [System v]                                              |
| [x] Show date   [ ] Show next event   [x] Move content slowly       |
| Sorted chronologically.                         [Cancel] [Save]   |
+-------------------------------------------------------------------+
```

Language choices are **System / English / Chinese**. Show the manual choices as **English / 中文** in both interfaces so users can recognize them regardless of the current language.

### 4.2 Editing Rules

1. Add creates a draft using the Gregorian calendar, current time zone, and the same wall-clock time on the next day, with seconds set to 00. Apply the same validity checks used for manually entered times.
2. Enter a title, select a calendar, and edit date, time, and time zone.
3. Immediately show the resolved Gregorian timestamp and remaining duration.
4. Re-sort valid drafts chronologically while preserving selection by UUID. Do not move an incomplete row during editing.
5. Disable Add at five events and display a localized maximum-count message. Deleting an event restores Add.
6. Save validates every event and persists the complete configuration together. Cancel discards the entire draft, including language and appearance changes.

Do not provide drag sorting because timestamps determine order. Keep expired events in the list with a localized status; users may edit or delete them.

Allow past timestamps, but clearly explain that the event will be skipped at runtime. If all timestamps are past, permit saving and explain that the screen saver will show its completion state.

### 4.3 Switching Calendars

For valid input, changing the input calendar preserves the absolute event timestamp and converts the displayed date components. Do not reinterpret unchanged numeric components under the other calendar.

Show a localized confirmation that the calendar changed without moving the target instant. If the corresponding lunar year is outside the supported range, explain the limitation and retain the original selection.

### 4.4 Language Selection and Resolution

Persist one preference: `system`, `en`, or `zhHans`. Default to `system` for new configurations and when upgrading a configuration that has no language field.

In System mode, inspect the user's top-priority system preferred language independently of the application's supported-localization fallback. Normalize its language tag and inspect its primary language subtag:

- `zh` selects the Chinese interface, including `zh-Hans`, `zh-Hant`, `zh-CN`, `zh-TW`, `zh-HK`, and other Chinese variants.
- Every other language selects English, including Japanese, Korean, French, and German.
- Missing or unrecognized language information selects English.

Only the first preferred system language determines the result. For example, English followed by Chinese still selects English. Geographic region, time zone, and calendar selection do not determine UI language. The first version provides Simplified Chinese for all Chinese variants; a separate Traditional Chinese translation is outside the initial scope.

Manual English or Chinese selection overrides system language until the user chooses System again. Changing the draft language immediately updates the settings interface and its embedded preview without losing edits or changing focus unnecessarily. Save applies it to running screen saver views through configuration synchronization; Cancel restores the previously saved language.

Resolve System mode when opening settings, starting a screen saver view, and after relevant preference refreshes. Reflect a system-language change at the latest on the next settings opening or screen saver start. Manual selection remains unchanged.

Localize titles generated by the application, unit labels, controls, validation errors, state messages, lunar month/day names, and date formatting. Keep user-entered titles, timestamps, identifiers, and time zones unchanged. Switching language must not alter calendar interpretation, event order, or resolved timestamps.

Use explicit English and Simplified Chinese resources with stable keys, complete message templates, and plural-aware English group labels. Avoid assembling sentences from translated fragments. Format dates using the resolved UI language and the event's explicit calendar/time zone, with a 24-hour clock and seconds in both languages. Use ASCII countdown digits in both interfaces.

| UI text | English | Chinese |
| --- | --- | --- |
| Settings title | Countdown Settings | 倒计时设置 |
| Language preference | Language | 语言 |
| Automatic mode | System | 跟随系统 |
| Units | DAYS / HOURS / MINUTES / SECONDS | 天 / 小时 / 分 / 秒 |
| Calendar choices | Gregorian / Chinese Lunar | 公历 / 农历 |
| Empty state | Add an event in screen saver options. | 请在屏幕保护程序选项中添加目标时间。 |
| Completion state | All events completed. | 所有目标已完成。 |
| Default event title | Event {number} | 目标 {number} |

This table shows translation examples; the surrounding design documentation remains English.

## 5. Calendar and Time-Zone Rules

### 5.1 Gregorian Input

Use the Gregorian calendar and a 24-hour clock with seconds. Recalculate valid days whenever year or month changes. If the selected day becomes invalid, require a new selection rather than silently normalizing it into the next month.

### 5.2 Chinese Lunar Input

Input consists of lunar year, month, day, and time:

- Display a familiar four-digit lunar year, meaning the lunar year beginning at Chinese New Year in that Gregorian year. Dates before Chinese New Year may belong to the previous lunar year.
- In Chinese, use conventional lunar month/day names. In English, use explicit labels such as “Lunar Month 1”, “Leap Month 6”, and “Day 1”, avoiding confusion with Gregorian months.
- Insert a leap month as a distinct option between its regular month and the following month.
- Offer 29 or 30 days according to the selected lunar month.
- Regenerate months after changing the year. If the old leap month does not exist, require reselection rather than converting it into a regular month.
- Always show the complete Gregorian equivalent and event time zone for confirmation.

Persist `isLeapMonth` independently; month number or list position alone cannot identify a lunar date.

### 5.3 Conversion Strategy

Prefer Foundation's Chinese calendar behind a dedicated service. Apple documents the [Chinese calendar identifier](https://developer.apple.com/documentation/foundation/calendar/identifier-swift.enum/chinese) and [DateComponents.isLeapMonth](https://developer.apple.com/documentation/foundation/datecomponents/isleapmonth). API availability does not establish the product's verified year range; boundary tests and authoritative date comparisons are required.

1. Establish the lunar-to-Gregorian date mapping using Chinese civil dates in `Asia/Shanghai`, independently of the system time zone.
2. Map the user-facing four-digit lunar year to Foundation's era/year representation. Do not directly assign the four-digit year to Chinese calendar `year`. Establish the lunar-year boundary and enumerate its month intervals.
3. Resolve month number, leap-month flag, and day within that lunar year to a Gregorian date.
4. Interpret that Gregorian date and entered time in the event's time zone to obtain an absolute timestamp.
5. Reverse-check lunar components and the leap-month flag before allowing Save.

Separate lunar date mapping from event location: first obtain the Gregorian civil date using Chinese calendar rules, then interpret the entered wall-clock time in the event's zone. Display the full result so overseas users can confirm the target instant. The initial event zone remains the current system zone.

If system conversion has unresolved discrepancies within the proposed range, evaluate an offline lunar table or library. Do not depend on online conversion or an unverified custom astronomical algorithm.

### 5.4 Time Zones and DST

Persist an IANA time-zone identifier and an absolute timestamp for each event. System time-zone changes must not move saved events; labels continue to use the event zone. Editing an event zone reinterprets its input date/time in the new zone and updates the displayed result.

- Nonexistent local time during a DST transition: block Save and request a valid time.
- Repeated local time: require selection of the first or second occurrence, show each UTC offset, and persist the choice and final timestamp.
- Validate input against the parsed result rather than accepting silent date normalization or a default repeated-time choice.

## 6. Countdown and Advancement

### 6.1 Event Selection

At each update, use absolute `now`, sort by `(resolvedTimestamp, createdOrder)`, and select the first event with `resolvedTimestamp > now`. Use `createdOrder` only to stabilize ordering for identical timestamps.

Do not persist a consumed-event index or delete expired entries automatically. After sleeping across multiple timestamps, select the nearest future event. If the system clock moves backward, an expired event may become future again; this is expected when following current system time.

### 6.2 Remaining-Time Calculation

```text
remaining = max(0, ceil(targetTimestamp - nowTimestamp))
days      = remaining / 86400
hours     = (remaining % 86400) / 3600
minutes   = (remaining % 3600) / 60
seconds   = remaining % 60
```

All divisions are integer divisions. Round up so a positive fraction of a second does not display zero early. Determine expiration using raw timestamps rather than rounded display values.

A countdown day is exactly 24 hours. Resolve calendar meaning during configuration. Recompute `target - now` at every update instead of decrementing a counter, avoiding accumulated errors from sleep, pauses, or scheduling delays.

### 6.3 Simultaneous and Closely Spaced Events

Group identical timestamps. Combine short titles, or show the first title with a localized additional-event count. Display an ordinal range such as “Events 2–3 / 5”. Keep individual entries in settings.

A simultaneous group completes together before advancement. Closely spaced but different timestamps retain their own timing; shorten completion messages rather than queueing outdated screens.

## 7. Technical Design

### 7.1 Technology Choices

| Layer | Proposal |
| --- | --- |
| Host integration | `ScreenSaver.framework` / `ScreenSaverView` |
| Views and settings | Swift + AppKit with native layout constraints |
| Date services | Foundation `Calendar`, `DateComponents`, and `TimeZone` |
| Persistence | Module-specific `ScreenSaverDefaults` with versioned Codable data |
| Localization | Explicit English and Simplified Chinese resources plus a shared language resolver |
| Development preview | Standalone AppKit application sharing views and the countdown engine |
| Build output | `.saver`, with a planned arm64 / x86_64 Universal build |
| Minimum OS | Proposed macOS 13; confirm against SDK, host loading, and hardware tests |

Use [`configureSheet`](https://developer.apple.com/documentation/screensaver/screensaverview/configuresheet), with the controller properly ending the sheet. Use [`ScreenSaverDefaults`](https://developer.apple.com/documentation/screensaver/screensaverdefaults) for module preferences.

Start with a minimal loadable saver and preview application rather than inheriting old build settings. Verify host compatibility before adding full functionality. Test system settings preview, full-screen operation, lock-screen behavior, and multiple displays separately; a working standalone preview is insufficient evidence of host compatibility.

### 7.2 Modules

```text
ConfigurationWindowController
    +-- DraftConfiguration / validation
    +-- CalendarConversionService / calendars and time zones
    +-- LocalizationService / language resolution and UI strings
    +-- ConfigurationStore / persistence

CountdownScreenSaverView
    +-- ConfigurationStore / snapshot loading
    +-- CountdownEngine / sorting, grouping, timing, and states
    +-- LocalizationService / shared language rules
    +-- CountdownContentView / layout and drawing

PreviewApp
    +-- Shared content view, engine, and localization service
```

Inject `now` into the engine for deterministic expiration and clock-change tests. Keep calendar conversion out of the per-second update path: resolve dates when saving and compare timestamps at runtime. All views and processes use the same localization policy and saved language preference.

### 7.3 Data Model

```text
Configuration
  schemaVersion: Int
  revision: UUID
  languagePreference: system | en | zhHans   // default: system
  events: [CountdownEvent]                  // at most five
  appearance: AppearanceSettings

CountdownEvent
  id: UUID
  title: String                            // user text; empty means generated label
  createdOrder: Int
  inputCalendar: gregorian | chinese
  inputYear: Int                           // product-defined four-digit year
  inputMonth: Int                          // 1–12
  inputDay: Int
  isLeapMonth: Bool                        // Chinese lunar input only
  hour / minute / second: Int
  timeZoneIdentifier: String
  repeatedTimeChoice: first | second | nil
  resolvedTimestamp: Double                // final absolute instant

AppearanceSettings
  showTargetDate: Bool
  showNextTarget: Bool
  moveContent: Bool
```

Store input components for editing and lunar labels, and the resolved timestamp for consistent countdowns across processes. Ordinary loading uses the saved timestamp so calendar implementation changes do not silently move events. Re-resolve when date-related fields are edited.

Store empty user titles as empty, generating localized defaults at display time so switching languages also updates default names. Do not persist the resolved System-mode language; derive it when needed. Older compatible configurations without a language preference default to System.

Validate count, fields, finite timestamps, zones, preference values, and schema version on load. Preserve unsupported versions and damaged data rather than overwriting them. Explain invalid entries in settings. On save failure, keep the sheet open, preserve the draft, and show a localized error.

### 7.4 Synchronization and Lifecycle

- Load a complete snapshot on start and reset transient stopped/expiration state.
- After Save, emit a cross-process update signal without event content. Receivers reload and validate the complete snapshot, including language preference.
- Treat notifications as an optimization. Check configuration revision at a low frequency to recover from missed notifications; verify actual preference visibility in the host.
- Use the screen saver animation callback for once-per-second calculations and redraw only on content changes. Schedule minor movement through the same callback.
- Stop updating when stopped; release runtime resources and remove observers on destruction. Do not share mutable completion state between display views.
- Recompute state and layout after clock changes, resume, or resizing; refresh automatic language resolution at lifecycle boundaries.

### 7.5 Installation and Distribution

Deliver a zipped `.saver` with English and Chinese installation instructions in the bilingual README. Recommend user-level installation in `~/Library/Screen Savers/` and configuration through System Settings. Plan Developer ID signing and notarization, validating the actual bundle and release process during implementation.

No network access, calendar-reading permission, or persistent menu-bar application is required. Store event configuration locally.

## 8. Acceptance Criteria

| Area | Required scenarios and expected results |
| --- | --- |
| Editing | Add, edit, delete, Cancel, Save; persistence survives reopening settings and restarting the saver |
| Count | 0, 1, and 5 events work; a sixth cannot be added; loaded data obeys the same limit |
| Order | Out-of-order entry sorts by absolute time; edits re-sort without losing selection |
| Expiration | Five sequential events advance correctly; no negative values; completion messages do not block close events |
| Simultaneous events | Grouped display and completion, stable ordering, no missing entries |
| Startup and sleep | Skip expired events and select the nearest future event after waking |
| Completion | Empty-list guidance and all-expired state; retain expired settings entries |
| Clock changes | Forward jump selects the valid event; backward jump recalculates against the new time |
| Gregorian boundaries | Leap February, month end, year change, midnight, and large day counts |
| Lunar conversion | New Year boundaries, last lunar month, 29/30-day months, leap months, years without leap months, range endpoints |
| Lunar accuracy | Compare representative years with authoritative calendars; valid round trips match; reject normalized invalid input |
| Calendar switching | Preserve the absolute timestamp; explain unsupported conversion ranges |
| Time zones | Sort across zones, preserve instants after system-zone changes, and handle nonexistent/repeated DST times |
| Automatic language | Chinese variants select Chinese; every other language selects English; English followed by Chinese remains English; absent information selects English |
| Manual language | English and Chinese override System; switching back restores automatic resolution; saved preference survives restart |
| Language editing | Immediate draft settings/preview update; Save synchronizes running views; Cancel restores saved behavior without losing unrelated saved data |
| Translation coverage | Settings, countdown, validation, empty/completed states, grouping, lunar labels, and dates use one resolved language |
| Language invariants | User titles, timestamps, calendars, zones, and event order remain unchanged; generated titles update |
| Localized layout | Long English labels and Chinese glyphs fit small previews, the sheet, and full-screen views |
| Persistence and sync | Saved data and language reach preview/runtime processes; Cancel does not persist; damaged data is retained without crashing |
| Display | Small preview, Retina, widescreen, portrait, multiple displays, long titles, and large day counts |
| Host compatibility | Loading, configuration, preview, start, stop, restart on every claimed OS/CPU combination |
| Resources | No sustained memory growth, unnecessary high-frequency redraws, or countdown work after stop |

Use focused unit tests for calendar, ordering, and language-resolution rules. Check layout in previews and screenshots. Verify host loading, preference synchronization, language changes, and multiple displays through integration and hardware testing.

## 9. Implementation Sequence and Deliverables

### Phase 1: Host and Display Foundation

Create a modern Xcode project, saver target, and preview application. Implement the four-column display, empty state, lifecycle, resizing, English/Chinese resource structure, and shared language resolver. Confirm host loading on the proposed systems.

### Phase 2: Multiple Events and Settings

Implement the five-event sheet, Gregorian dates, time zones, Save/Cancel, System/English/Chinese selection, sorting, simultaneous groups, advancement, completion state, and cross-process synchronization.

### Phase 3: Lunar Dates and Boundaries

Implement lunar-year mapping, month/leap-month selection, validity checks, localized lunar labels, Gregorian confirmation, calendar switching, and DST handling. Verify the supported year range.

### Phase 4: Release Verification

Finish multiple displays, content movement, auxiliary-text options, localized error states, and equivalent English/Chinese README installation instructions. Verify translation coverage, host compatibility, resource use, signing, and notarization.

Deliver source code, an installable `.saver`, a development preview application, date/language rule tests, a bilingual README, English design documents, and a verified platform-support list.

## 10. Future Extensions

Consider annual recurrence, lunar birthday policies, additional themes, import/export, and migration from the old Countdown preferences after the first version is stable. Automatic migration requires explicit user intent and identification of the actual old preference domain; the first version does not read or modify old application settings by default.

Before adding recurrence, define regular/leap-month selection, years missing the selected leap month, missing lunar day 30, and Gregorian February 29 behavior.
