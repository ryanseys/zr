# a[*x] op= v calls x.to_a once; a numbered reference too big for a
# variable is nil; a global never set warns under $VERBOSE; a clone keeps
# its singleton class's constants; a static command is a frozen String.
class Splat
  def to_a
    puts "to_a"
    [0]
  end
end
a = [1]
a[*Splat.new] += 1
a[*Splat.new] ||= 5
a[*Splat.new] &&= 7
p a

"a" =~ /(.)/
p $4294967296

$stderr = $stdout
$VERBOSE = true
p $never_set_global_for_test
$VERBOSE = false

o = Object.new
o.singleton_class.const_set(:CONST, 42)
p o.clone.singleton_class::CONST

def `(s) = [s, s.frozen?]
p `static`
x = 1
p `dynamic #{x}`
