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

# `Date.parse` completes the fields: everything ABOVE the most significant one
# given is unknown, and everything below it takes its minimum.
p Date.parse("2024-01-15").to_s
p Date.parse("2024-015").to_s
p Date.parse("2024-W03-1").to_s
p Date.parse("Aug 2000").to_s
p Date.parse("2024-01-15T10:30:00Z").to_s
p Date.parse("15-Jan-2024").to_s
begin
  Date.parse("10:30")
rescue ArgumentError => e
  p [:no_date, e.message]
end
begin
  Date.parse("2024")
rescue ArgumentError => e
  p [:not_a_day, e.message]
end

