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

# RFC 2822 and HTTP-date, whose weekday name is recorded and then ignored.
p Date._parse("Mon, 15 Jan 2024 10:30:00 +0900")
p Date._parse("Fri, 15 Jan 2024 10:30:00 GMT")
p Date._parse("Sat, 03 Feb 2024 04:05:06 -0000")
p Date._parse("Thu Nov 29 14:33:20 2001")
p Date._parse("Wed, 15 May 2024")

