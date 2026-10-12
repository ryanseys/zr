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

# A bare digit run is read by its LENGTH, with no validation at all.
p Date._parse("20240115")
p Date._parse("20240115T103000Z")
p Date._parse("20240115103000")
p Date._parse("2000")
p Date._parse("24")
p Date._parse("012")
p Date._parse("12345")
p Date._parse("1234567")
p Date._parse("3rd")
p Date._parse("15th")

