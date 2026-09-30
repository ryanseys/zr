# A negative Float ** a fractional exponent gives a Complex, as in CRuby.
begin
  p((-2.0) ** 0.5)
rescue => e
  puts "#{e.class}: raised"
end
p(2.0 ** 0.5)
p((-2.0) ** 2.0)
p((-8.0) ** (1.0 / 3)) rescue puts "raised2"
