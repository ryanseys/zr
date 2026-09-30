# `Date._parse` -- the heuristic scanner `Date.parse`, `DateTime.parse` and
# `Time.parse` all read their fields out of. Every line here is oracle-verified
# against ruby 4.0.7, including the KEY ORDER: the hash records fields in the
# order the cascade found them (weekday, then clock and zone, then the date),
# so the order is part of the answer.
#
# Known divergence: a string with no date in it raises ArgumentError here where
# ruby raises `Date::Error`, a subclass of it that zr does not model (the date
# extension is native, with no Ruby half to declare the class in).
require "date"

# A clock on its own, with a meridian marker or a zone.
p Date._parse("10:30")
p Date._parse("10:30:00.5")
p Date._parse("12:00 pm")
p Date._parse("12:00 am")
p Date._parse("1:30pm")
p Date._parse("23:59:60")
p Date._parse("10:30 JST")
p Date._parse("10:30 -0530")
p Date._parse("10:30 gmt-3")
p Date._parse("10:30 Eastern Standard Time")
p Date._parse("10:30 EST5EDT")

