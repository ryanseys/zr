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

# Commentary in parentheses is dropped, as RFC 2822 allows.
p Date._parse("2024-01-15 (a comment) 10:30")
p Date._parse("  2024-01-15  ")

