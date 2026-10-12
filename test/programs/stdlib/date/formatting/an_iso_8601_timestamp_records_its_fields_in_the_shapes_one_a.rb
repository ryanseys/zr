# `Date._parse` -- the heuristic scanner `Date.parse`, `DateTime.parse` and
# `Time.parse` all read their fields out of. Every line here is oracle-verified
# against ruby, including the KEY ORDER: the hash records fields in the
# order the cascade found them (weekday, then clock and zone, then the date),
# so the order is part of the answer.
#
# Known divergence: a string with no date in it raises ArgumentError here where
# ruby raises `Date::Error`, a subclass of it that zr does not model (the date
# extension is native, with no Ruby half to declare the class in).
require "date"

# ISO 8601, in the shapes a timestamp actually arrives in.
p Date._parse("2024-01-15")
p Date._parse("2024-01-15T10:30:00Z")
p Date._parse("2024-01-15T10:30:00+09:00")
p Date._parse("2024-01-15T10:30:00.123456+09:00")
p Date._parse("2024-01-15 10:30:00 UTC")
p Date._parse("2024-01-15T10:30")
p Date._parse("2001-02-03T04:05:06.123456789")
p Date._parse("2024-01-15T10:30:00,5Z")

