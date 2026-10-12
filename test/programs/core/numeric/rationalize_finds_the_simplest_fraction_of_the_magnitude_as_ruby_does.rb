# rationalize finds the simplest fraction for the magnitude, then puts
# the sign back. A Float interval stays Float, -0.0 counts as not
# negative, and the argument's abs comes before any other check.
def show(label)
  puts "#{label}: #{yield.inspect}"
rescue => e
  puts "#{label}: #{e.class}: #{e.message}"
end

[1, 1.5, -2, 0, 1r / 10, 0.0, 0.01].each do |eps|
  [3r / 4, -1r / 3, -7r / 3, 1r / 3, -1r].each do |r|
    show("#{r}.rationalize(#{eps})") { r.rationalize(eps) }
  end
  [-0.0, 0.0, 2.5, -2.5, 0.333, -0.333, 1e-20, 3.14159].each do |f|
    show("#{f}.rationalize(#{eps})") { f.rationalize(eps) }
  end
  show("Complex(-0.25, 0).rationalize(#{eps})") { Complex(-0.25, 0).rationalize(eps) }
end

[nil, "l", :a, [1]].each do |eps|
  show("rational, #{eps.inspect}") { (3r / 4).rationalize(eps) }
  show("float, #{eps.inspect}") { 2.5.rationalize(eps) }
  show("NaN, #{eps.inspect}") { Float::NAN.rationalize(eps) }
  show("complex, #{eps.inspect}") { Complex(0.5, 0).rationalize(eps) }
end

show("NaN within 1") { Float::NAN.rationalize(1) }
show("Infinity within 1") { Float::INFINITY.rationalize(1) }
show("no argument") do
  [0.1.rationalize, -0.1.rationalize, -0.0.rationalize, 1.5.rationalize, -3.0.rationalize,
   (-1r / 3).rationalize, Complex(-0.25, 0).rationalize, 1e-300.rationalize, -1e300.rationalize]
end
show("too many") { 2.5.rationalize(1, 2) }
show("complex too many") { Complex(1, 0).rationalize(1, 2) }
