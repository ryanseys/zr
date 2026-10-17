# date_core.c keeps a Float part's fraction a Float, and adds it to the
# day with its Float rounding to whole nanoseconds (d_trunc, add_frac,
# d_lite_plus). A Rational part stays exact.
require "date"

[19.1, 19.5, 0.3, 59.999999999, Rational(191, 10), 19.000000001].each do |second|
  d = DateTime.new(2018, 1, 14, 22, 25, second)
  p [second, d.sec, d.sec_fraction, d.strftime("%T.%N")]
end
p DateTime.new(2018, 1, 14, 22, 25, 19.1, "+9").sec_fraction
p DateTime.new(2018, 1, 14, 22, 25.5).strftime("%T.%N"), DateTime.new(2018, 1, 14, 22.25).strftime("%T.%N")
p DateTime.new(2018, 1, 14.75).strftime("%F %T.%N"), DateTime.new(2018, 1, 14, -1.5).strftime("%F %T") rescue p $!
p DateTime.jd(2458133.1).strftime("%F %T.%N"), DateTime.ordinal(2018, 14.5).strftime("%F %T")
p DateTime.new(2018, 1, 14, 22, 25, 19.1) == DateTime.parse("2018-01-14T22:25:19.1")
p DateTime.commercial(2018, 2, 7.25).strftime("%F %T")
begin
  DateTime.new(2018, 1, 14, 22.5, 1)
rescue Date::Error => e
  p e
end
