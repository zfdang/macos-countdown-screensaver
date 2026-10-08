# Calendar Data and Validation

The runtime uses a compact, offline Chinese lunar month table for lunar years 1901–2100. It stores each lunar New Year's Gregorian date, leap-month number, and sequential month lengths. Gregorian input supports years 1901–9999. Annual recurrence is outside this version.

The primary data source is the [Hong Kong Observatory Gregorian–Lunar Calendar Conversion Table](https://www.hko.gov.hk/en/gts/time/conversion.htm), specifically its annual English text files. `scripts/generate-lunar-table.py` extracts month boundaries and validates 12/13 months per lunar year and 29/30 days per month. It caches downloaded source files under `.build/hko/`; ordinary builds, tests, and runtime operation do not download anything.

The final lunar month of 2100 ends immediately before 2101-01-29. This upper boundary was independently checked with `lunar-typescript` 1.8.6. It allows all of lunar year 2100, including dates in Gregorian January 2101, while rejecting lunar year 2101 itself.

## Why the Runtime Does Not Use Foundation's Chinese Calendar

Initial full-range tests found that Foundation returned lunar day zero on 2057-09-28 and 2097-08-07 on the development machine. Using month starts from one API and day components from another would reject valid dates around those boundaries. A bundled civil-date table avoids OS-dependent calendar calculations, and pure UTC civil-date arithmetic avoids historical time-zone/DST drift. Event time zones are applied only after conversion to a Gregorian civil date.

The Observatory itself [documents uncertainty in distant future new-moon boundaries](https://www.hko.gov.hk/en/gts/time/conversion.htm). This implementation follows its published dates consistently; it does not perform astronomical prediction.

## Tests

- Every valid lunar date in all 200 supported years converts to an absolute timestamp and back without changing lunar year, month, day, or leap-month identity.
- New Year, leap-month, small-month, range, and Gregorian January 2101 boundaries are covered.
- Hong Kong Observatory conversion cases cover New Year and leap-month dates; full-range tests check leap-month identity and valid month lengths.
- DST gaps, repeated hours, half-hour transitions, and skipped civil days are tested separately from lunar mapping.
