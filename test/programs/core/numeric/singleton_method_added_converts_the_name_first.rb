# Numeric#singleton_method_added converts the name as rb_to_id does
# before anything else: a value that is no Symbol or String is a
# TypeError that names it. Found by zr-dev fuzz.
def try(label)
  puts "#{label}: #{yield.inspect}"
rescue StandardError => e
  puts "#{label}: #{e.class}: #{e.message}"
end

try("0, true") { 0.singleton_method_added(true) }
try("0, nil") { 0.public_send(:singleton_method_added, nil) }
try("1.5, 1") { 1.5.singleton_method_added(1) }
try("0, :x") { 0.singleton_method_added(:x) }
try("0, 'y'") { 0.singleton_method_added("y") }
try("big, :x") { (2**70).singleton_method_added(:x) }
try("define on a Rational") do
  r = 1r
  def r.x = 1
end
