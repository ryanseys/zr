# A Bignum converts a shift count as rb_to_int does, one bit index and
# a radix as NUM2LONG does, and to_s takes at most one argument.
def show(label)
  puts "#{label}: #{yield.inspect}"
rescue => e
  puts "#{label}: #{e.class}: #{e.message}"
end

[2**70, -(2**70), 7].each do |n|
  [nil, 1.5, 2r, "a", :a].each do |x|
    show("#{n} << #{x.inspect}") { n << x }
    show("#{n} >> #{x.inspect}") { n >> x }
    show("#{n}[#{x.inspect}]") { n[x] }
    show("#{n}[#{x.inspect}, 1]") { n[x, 1] }
  end
  show("#{n}.to_s(nil)") { n.to_s(nil) }
  show("#{n}.to_s(2, 1)") { n.to_s(2, 1) }
  show("#{n}.to_s(16)") { n.to_s(16) }
  show("#{n}.to_s(1.9)") { n.to_s(36.9) }
  show("#{n}.to_s(37)") { n.to_s(37) }
  show("#{n}.to_s") { n.to_s }
  show("#{n}.inspect") { n.inspect }
end
