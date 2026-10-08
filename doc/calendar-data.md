# Calendar Data and Reference Validation

The runtime uses a compact, offline Chinese lunar month table for lunar years 1901–2100. It stores each lunar New Year's Gregorian date, leap-month number, and sequential month lengths. Gregorian input supports years 1901–9999. Annual recurrence is outside this version.

The primary data source is the [Hong Kong Observatory Gregorian–Lunar Calendar Conversion Table](https://www.hko.gov.hk/en/gts/time/conversion.htm), specifically its annual English text files. `scripts/generate-lunar-table.py` extracts month boundaries and validates 12/13 months per lunar year and 29/30 days per month. It caches downloaded source files under `.build/hko/`; ordinary builds, tests, and runtime operation do not download anything.

The final lunar month of 2100 ends immediately before 2101-01-29. This upper boundary was independently checked with `lunar-typescript` 1.8.6. It allows all of lunar year 2100, including dates in Gregorian January 2101, while rejecting lunar year 2101 itself.

## Why the Runtime Does Not Use Foundation's Chinese Calendar

Initial full-range tests found that Foundation returned lunar day zero on 2057-09-28 and 2097-08-07 on the development machine. Using month starts from one API and day components from another would reject valid dates around those boundaries. A bundled civil-date table avoids OS-dependent calendar calculations, and pure UTC civil-date arithmetic avoids historical time-zone/DST drift. Event time zones are applied only after conversion to a Gregorian civil date.

The Observatory itself [documents uncertainty in distant future new-moon boundaries](https://www.hko.gov.hk/en/gts/time/conversion.htm). This implementation follows its published dates consistently; it does not perform astronomical prediction.

## Comparison with day-memory

Reviewed the user-provided reference project at `/Users/zfdang/workspaces/day-memory`, including:

- `miniprogram/core/occurrence.ts`: calendar conversion, leap-month identity, month lengths, and input validation.
- `miniprogram/core/date.ts`: separation of civil-date arithmetic from device time zones.
- `miniprogram/components/lunar-picker/index.ts`: distinct leap-month options and year-dependent day counts.
- `tests/fixtures/lunar-cases.json` and its TypeScript tests: bidirectional conversion, leap-month, month-length, and formatting fixtures.

Compared all 200 supported years with the installed `lunar-typescript` 1.8.6 implementation used by day-memory. There was one difference: the month-8/month-9 boundary in 2057. This project's table follows the Observatory's September 28 boundary; the comparison library follows September 29. The other 199 years matched in New Year date, leap month, and every month length.

The checked-in `Tests/CountdownCoreTests/Fixtures/day-memory-lunar.json` includes conversion, leap-month, and month-length facts from that reference. It deliberately excludes annual recurrence behavior: a one-time target with a nonexistent leap month or day 30 is rejected rather than silently changed to a regular month or day 29.

## Tests

- Every valid lunar date in all 200 supported years converts to an absolute timestamp and back without changing lunar year, month, day, or leap-month identity.
- New Year, leap-month, small-month, range, and Gregorian January 2101 boundaries are covered.
- Reference conversions, leap months (including 2033 leap month 11), and month lengths are checked independently.
- DST gaps, repeated hours, half-hour transitions, and skipped civil days are tested separately from lunar mapping.
