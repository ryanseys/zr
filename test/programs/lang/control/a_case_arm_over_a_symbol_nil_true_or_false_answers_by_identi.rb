# A `case` arm over a symbol, nil, true or false asks Object#=== of the
# literal, which is identity where the class's `==` is BasicObject's
# (SHAPE_EQQ at the site, and zr_obj_eqq answers with no send); a
# receiver with a `==` of its own, an Integer, a String and a Float
# keep their own answers.
def k(x)
  case x
  when :a then 1
  when :b, :c then 2
  when nil then 3
  when true then 4
  when 1 then 5
  when "s" then 6
  when 1.0 then 7
  else 0
  end
end
p [:a, :b, :c, :d, nil, true, false, 1, 1.0, "s", 2**70].map { |x| k(x) }
class Sym2; def ==(o) = true; end
p (case 1 when Sym2.new then :yes else :no end)
p :a === :a, :a === :b, nil === nil, nil === false, Object.new === Object.new
o = Object.new
p o === o, o === 1
n = 0
100_000.times { |i| n += k(i.even? ? :b : :c) }
p n
