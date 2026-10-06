# On an arity mismatch, `send` raises a RESCUABLE ArgumentError, as Ruby
# does. The program survives every mismatch and the final line prints.
# All three message shapes -- fixed `N`, range `N..M`, and the rest form
# `N+` -- are oracle-verified against ruby 4.0.7.

class A
  def fixed(a) = a
  def rng(a, b = 2) = a + b
  def restp(a, *b) = a
end
o = A.new
[[:fixed, []], [:fixed, [1, 2]], [:rng, []], [:rng, [1, 2, 3]], [:restp, []]].each do |m, args|
  begin
    o.send(m, *args)
  rescue ArgumentError => e
    puts "#{m}: #{e.message}"
  end
end
puts "survived"
