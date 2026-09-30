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

# The zone table `:offset` is filled from, exercised through the scanner (CRuby
# keeps `zone_to_diff` to itself, so there is no public row to call directly).
["+09:00", "-0530", "UTC", "PST", "CEST", "A", "Y", "nowhere"].each do |z|
  p [z, Date._parse("10:30 #{z}")[:offset]]
end
