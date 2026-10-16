# date_core.c checks each part of a date for a Numeric, reads an offset
# through to_r as offset_to_sec does, and steps by the sign of the step's
# own <=>; DateTime has no today.
require "date"
def t(label)
  print label, ": "
  p yield
rescue Exception => e
  p [e.class, e.message]
end
o = Object.new
[[Date, :julian_leap?, [o]], [Date, :gregorian_leap?, [o]], [Date, :leap?, [o]], [Date, :jd, [o]], [Date, :new, [o]], [Date, :new, [1, o]], [Date, :new, [1, 1, o]],
 [Date, :ordinal, [o]], [Date, :ordinal, [1, o]], [Date, :commercial, [o]], [Date, :commercial, [1, o]], [Date, :commercial, [1, 1, o]],
 [DateTime, :jd, [o]], [DateTime, :jd, [1, o]], [DateTime, :jd, [1, 1, o]], [DateTime, :jd, [1, 1, 1, o]],
 [DateTime, :new, [o]], [DateTime, :new, [1, o]], [DateTime, :new, [1, 1, o]], [DateTime, :new, [1, 1, 1, o]], [DateTime, :new, [1, 1, 1, 1, o]], [DateTime, :new, [1, 1, 1, 1, 1, o]],
 [DateTime, :ordinal, [o]], [DateTime, :ordinal, [1, o]], [DateTime, :ordinal, [1, 1, o]], [DateTime, :ordinal, [1, 1, 1, o]], [DateTime, :ordinal, [1, 1, 1, 1, o]],
 [DateTime, :commercial, [o]], [DateTime, :commercial, [1, o]], [DateTime, :commercial, [1, 1, o]], [DateTime, :commercial, [1, 1, 1, o]], [DateTime, :commercial, [1, 1, 1, 1, o]], [DateTime, :commercial, [1, 1, 1, 1, 1, o]],
 [Date, :julian_leap?, ["4"]], [Date, :gregorian_leap?, [nil]], [Date, :julian_leap?, [4.0]], [Date, :gregorian_leap?, [Rational(2000)]], [Date, :gregorian_leap?, [1900.5]]].each do |klass, name, args|
  t("#{klass}.#{name}(#{args.map { _1.equal?(o) ? "o" : _1.inspect }.join(", ")})") { klass.public_send(name, *args) }
end
t("DateTime.respond_to?(:today)") { DateTime.respond_to?(:today) }
t("DateTime.today") { DateTime.today }
t("Date.respond_to?(:today)") { Date.respond_to?(:today) }

class Rat < Numeric
  def to_r = self
end
class One < Numeric
  def to_r = 1
end
class Half < Numeric
  def to_r = 0.5
end
class Str < Numeric
  def to_r = "+09:00"
end
d = DateTime.new(2002, 3, 14)
[Rational(9, 24), "+0900", Rat.new, One.new, Half.new, Str.new, Rational(1, 86400 * 2), Rational(3, 2), 2**70, Rational(2**70, 3), :x, nil, 1.5, -1, 1, 2].each do |of|
  t("new_offset(#{[Rat, One, Half, Str].include?(of.class) ? of.class : of.inspect})") { d.new_offset(of).offset }
end

p1 = Date.new(2000, 1, 1)
q = Date.new(1999, 12, 31)
nilcmp = Object.new
def nilcmp.<=>(*) = nil
two = Object.new
def two.<=>(*) = 2
t("step nil-cmp") { p1.step(q, nilcmp).to_a }
t("step nil-cmp block") { p1.step(q, nilcmp) { } }
t("step two") { a = []; p1.step(q, two) { |d| a << d }; a }
t("step 0 enum") { p1.step(q, 0).class }
t("step 0 block") { n = 0; p1.step(q, 0) { n += 1; break n if n == 3 } }
t("step -1") { p1.step(q, -1).map(&:to_s) }
t("step 1/2") { Date.new(2000, 1, 1).step(Date.new(2000, 1, 2), Rational(1, 2)).map(&:to_s) }
t("step 'x'") { p1.step(q, "x") { } }
t("step no limit") { p1.step }
