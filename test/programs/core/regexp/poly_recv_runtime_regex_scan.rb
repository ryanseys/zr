# A poly receiver scanning against a pattern the compiler cannot resolve to a
# literal.
#
# An inline Regexp.new, a local holding one, or an interpolated literal all
# work as the pattern, when the receiver is a String. A receiver that is not
# a String raises NoMethodError, and is not turned into an empty scan.

PAT = /(\d)(\w)/
mixed = ["a1b2", 7]
poly = mixed[0]

p poly.scan(/\d/)
p poly.scan(PAT)

lpat = /(\d)(\w)/
p poly.scan(lpat)

p poly.scan(Regexp.new("\\d"))
rt = Regexp.new("(\\d)(\\w)")
p poly.scan(rt)
d = "\\d"
p poly.scan(/#{d}/)
p poly.scan("1")

n = mixed[1]
begin
  n.scan(/\d/)
  p "no raise"
rescue NoMethodError
  p "NoMethodError"
end

begin
  n.scan(Regexp.new("\\d"))
  p "no raise"
rescue NoMethodError
  p "NoMethodError"
end
