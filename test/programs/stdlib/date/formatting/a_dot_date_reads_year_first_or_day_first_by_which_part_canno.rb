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

# Separator forms. A dot date reads year-first or day-first depending on which
# end carries the four-digit year.
p Date._parse("2024/01/15")
p Date._parse("2024.01.15")
p Date._parse("5.6.2024")
p Date._parse("31.12.99")
p Date._parse("7/23")
p Date._parse("2024/1")
p Date._parse("12/2024")
p Date._parse("1/2/3")

