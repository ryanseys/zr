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

# The month-NAME forms, in either order and with or without a year.
p Date._parse("15 Jan 2024")
p Date._parse("Jan 15 2024")
p Date._parse("January 15, 2024")
p Date._parse("15-Jan-2024")
p Date._parse("Aug 31")
p Date._parse("Aug 2000")
p Date._parse("Aug 3rd 2000")
p Date._parse("Jan '99")
p Date._parse("'99 Jan 15")
p Date._parse("Aug")

