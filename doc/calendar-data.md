# Calendar Data and Validation

The runtime uses a compact, offline Chinese lunar month table for lunar years 1901–2100. It stores each lunar New Year's Gregorian date, leap-month number, and sequential month lengths. Gregorian input supports years 1901–9999. Annual recurrence is outside this version.

The primary data source is the [Hong Kong Observatory Gregorian–Lunar Calendar Conversion Table](https://www.hko.gov.hk/en/gts/time/conversion.htm), specifically its annual English text files. `scripts/generate-lunar-table.py` extracts month boundaries and validates 12/13 months per lunar year and 29/30 days per month. It caches downloaded source files under `.build/hko/`; ordinary builds, tests, and runtime operation do not download anything.

The final lunar month of 2100 ends immediately before 2101-01-29. This upper boundary was independently checked with `lunar-typescript` 1.8.6. It allows all of lunar year 2100, including dates in Gregorian January 2101, while rejecting lunar year 2101 itself.

## Why the Runtime Does Not Use Foundation's Chinese Calendar

Initial full-range tests found that Foundation returned lunar day zero on 2057-09-28 and 2097-08-07 on the development machine. Using month starts from one API and day components from another would reject valid dates around those boundaries. A bundled civil-date table avoids OS-dependent calendar calculations, and pure UTC civil-date arithmetic avoids historical time-zone/DST drift. Event time zones are applied only after conversion to a Gregorian civil date.

### Observed Foundation Differences

A full daily comparison of lunar years 1901–2100 on macOS 15.8 found five affected lunar years, each with 30 differing dates. The comparison used UTC noon and checked lunar month, day, and leap-month identity against the bundled table. These observations describe that OS version; regression tests assert fixed Observatory facts rather than requiring Foundation to keep producing the same errors.

| Lunar year | Differing Gregorian dates (inclusive) | Observatory/table interpretation at the start |
| --- | --- | --- |
| [1914](https://www.hko.gov.hk/en/gts/time/calendar/text/files/T1914e.txt) | 1914-11-17–1914-12-16 | Regular month 10, day 1 |
| [1916](https://www.hko.gov.hk/en/gts/time/calendar/text/files/T1916e.txt) | 1916-02-03–1916-03-03 | Regular month 1, day 1 |
| [1920](https://www.hko.gov.hk/en/gts/time/calendar/text/files/T1920e.txt) | 1920-11-10–1920-12-09 | Regular month 10, day 1 |
| [2057](https://www.hko.gov.hk/en/gts/time/calendar/text/files/T2057e.txt) | 2057-09-28–2057-10-27 | Regular month 9, day 1 |
| [2097](https://www.hko.gov.hk/en/gts/time/calendar/text/files/T2097e.txt) | 2097-08-07–2097-09-05 | Regular month 7, day 1 |

For 1914, 1916, and 1920, Foundation reported the preceding month's day 30 on the first date and remained one day behind throughout the affected month. The Observatory and an independent `lunar-typescript` check agree with the bundled table. For 2057 and 2097, Foundation reported day zero on the first date and remained one day behind through the month.

The Observatory itself [documents uncertainty in distant future new-moon boundaries](https://www.hko.gov.hk/en/gts/time/conversion.htm). This implementation follows its published dates consistently; it does not perform astronomical prediction.

## Independent Validation and Pinned Boundaries

An earlier cross-check against `lunar-typescript` 1.8.6 compared New Year dates, leap-month numbers, and every month length across all 200 supported lunar years. Only 2057 differed: the Observatory begins month 9 on September 28, while the comparison library begins it on September 29. This is within the Observatory's documented distant-future uncertainty; the table deliberately retains September 28. This validation record does not introduce a library dependency or external project fixtures into ordinary builds or tests.

The [2033 Observatory table](https://www.hko.gov.hk/en/gts/time/calendar/text/files/T2033e.txt) repeats month 11: regular month 11 starts on November 22 and lasts 30 days; leap month 11 starts on December 22 and lasts 29 days. The [2034 table](https://www.hko.gov.hk/en/gts/time/calendar/text/files/T2034e.txt) places lunar month 12 on January 20. An independent library check also confirmed leap month 11. Fixed regression cases lock the regular/leap distinction, both month boundaries, month lengths, and rejection of leap-month day 30.

The 2057 regression cases pin September 27 (month 8, day 29), September 28 (month 9, day 1), October 27 (month 9, day 30), and October 28 (month 10, day 1), in both conversion directions. Historical cases pin the first and last affected dates in 1914, 1916, and 1920.

## Tests

- Every valid lunar date in all 200 supported years converts to an absolute timestamp and back without changing lunar year, month, day, or leap-month identity.
- New Year, leap-month, small-month, range, and Gregorian January 2101 boundaries are covered.
- Hong Kong Observatory conversion cases cover New Year and leap-month dates; full-range tests check leap-month identity and valid month lengths.
- Focused boundary tests lock 2033 leap month 11, the published 2057 September boundary, and the historical Foundation difference intervals.
- DST gaps, repeated hours, half-hour transitions, and skipped civil days are tested separately from lunar mapping.

Regenerating the table uses the same two-space Swift indentation and inline-comment spacing as the checked-in source. With unchanged Observatory inputs, regeneration produces no source diff.
