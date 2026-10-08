#!/usr/bin/env python3
"""Regenerate civil-date facts from HKO's public Gregorian/lunar conversion tables.
Runtime and ordinary builds are offline; this maintenance script alone uses the network.
"""
import concurrent.futures
import datetime
import pathlib
import re
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
CACHE = ROOT / '.build' / 'hko'
CACHE.mkdir(parents=True, exist_ok=True)

def fetch(year):
    path = CACHE / f'{year}.txt'
    if not path.exists():
        url = f'https://www.hko.gov.hk/en/gts/time/calendar/text/files/T{year}e.txt'
        with urllib.request.urlopen(url, timeout=30) as response:
            path.write_bytes(response.read())
    starts = []
    for line in path.read_text(encoding='latin-1').splitlines():
        match = re.match(r'(\d{4})/(\d+)/(\d+)\s+(\d+)(?:st|nd|rd|th) Lunar [Mm]onth', line)
        if match:
            y, m, d, lunar_month = map(int, match.groups())
            starts.append((datetime.date(y, m, d), lunar_month))
    if len(starts) < 12:
        raise ValueError(f'Incomplete source for {year}')
    return starts

with concurrent.futures.ThreadPoolExecutor(max_workers=6) as executor:
    starts = sorted(item for annual in executor.map(fetch, range(1901, 2101)) for item in annual)
# Upper boundary: 2101 New Year is Jan 29. It is used only to delimit lunar year 2100.
starts.append((datetime.date(2101, 1, 29), 1))
records = []
for year in range(1901, 2101):
    first = next(i for i, (date, month) in enumerate(starts) if date.year == year and month == 1)
    end = next(i for i in range(first + 1, len(starts)) if starts[i][1] == 1)
    months = starts[first:end]
    assert len(months) in (12, 13)
    leap = 0
    lengths = []
    for offset, (date, month) in enumerate(months):
        length = (starts[first + offset + 1][0] - date).days
        assert length in (29, 30), (year, month, length)
        if offset and month == months[offset - 1][1]:
            leap = month
        lengths.append(str(length))
    first_date = months[0][0]
    records.append(f'        ({first_date.month}, {first_date.day}, {leap}, "{",".join(lengths)}"), // {year}')
source = '''// Generated civil-date facts, not an astronomical algorithm.
// Source: Hong Kong Observatory Gregorian-Lunar Calendar Conversion Tables, 1901–2100.
// https://www.hko.gov.hk/en/gts/time/conversion.htm
// Regenerate with scripts/generate-lunar-table.py. See doc/calendar-data.md.
import Foundation

enum LunarTable {
    // Gregorian New Year month/day, leap month (0 if none), sequential month lengths.
    static let years: [(Int, Int, Int, String)] = [
''' + '\n'.join(records) + '\n    ]\n}\n'
(ROOT / 'Sources/CountdownCore/LunarTable.swift').write_text(source)
print(f'Generated {len(records)} lunar years from HKO month boundaries')
