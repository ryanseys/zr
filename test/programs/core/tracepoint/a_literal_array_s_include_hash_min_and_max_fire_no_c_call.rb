# ruby 4.1 runs include? on any Array literal, and hash, min and max on one
# that is not static, with no send (opt_newarray_send, opt_duparray_send),
# so TracePoint sees no c_call. Some argument forms keep the send.
X = 1
class O; def foo = 1; end
@iv = 1
x = 2
o = O.new
def foo = 1
forms = {
  "nil" => -> { [x, 1].include?(nil) }, "nil_s" => -> { [1, 2].include?(nil) },
  "1" => -> { [x, 1].include?(1) }, "1_s" => -> { [1, 2].include?(1) }, "0" => -> { [x, 1].include?(0) },
  "str" => -> { [x, 1].include?("s") }, "str_s" => -> { [1, 2].include?("s") },
  "sym" => -> { [x, 1].include?(:s) }, "o.foo" => -> { [x, 1].include?(o.foo) },
  "o.foo_s" => -> { [1, 2].include?(o.foo) }, "foo" => -> { [x, 1].include?(foo) },
  "foo_s" => -> { [1, 2].include?(foo) }, "iv" => -> { [x, 1].include?(@iv) },
  "self" => -> { [x, 1].include?(self) }, "x+1" => -> { [x, 1].include?(x + 1) }, "X" => -> { [x, 1].include?(X) },
  "X_s" => -> { [1, 2].include?(X) }, "true" => -> { [x].include?(true) }, "1.5" => -> { [x].include?(1.5) },
  "re" => -> { [x].include?(/a/) }, "range" => -> { [x].include?(1..2) }, "empty" => -> { [].include?(x) },
  "o.foo.succ" => -> { [x].include?(o.foo.succ) }, "hash" => -> { [x, 1].hash }, "hash_s" => -> { [1, 2].hash },
  "max" => -> { [x, 1].max }, "max_s" => -> { [1, 2].max }, "min" => -> { [x, 1].min },
  "splat" => -> { [1, 2].include?(*[2]) }, "safe" => -> { [x]&.include?(x) },
  "block" => -> { [x].include?(x) { 1 } }, "two" => -> { [x].include?(x, &nil) },
}
forms.each do |name, f|
  ev = []
  tp = TracePoint.new(:c_call) { |t| ev << t.method_id if %i[include? hash max min].include?(t.method_id) }
  r = tp.enable { f.call }
  puts "#{name}=#{ev.empty? ? "opt" : "send"} #{r.is_a?(Integer) && r.abs > 100 ? "int" : r.inspect}"
end

# The results are Array's own.
p [x, 1].include?(2), [x, 1].include?(3), [1, 2].include?(2), [x, nil].include?(nil)
p [x, 1].hash == [2, 1].hash, [x, [1]].hash == [2, [1]].hash, [].include?(nil)
p [x, 1.0].include?(1), [x, "a"].include?("a"), [x, 1].max, [x, 1].min

# The receiver's items come first, then the argument.
order = []
p [order << :a && 1, (order << :b; 2)].include?((order << :c; 2)), order

# A program that redefines the method gets its own method.
class Array
  alias old_include? include?
  def include?(v) = "mine #{v}"
  alias old_hash hash
  def hash = 42
end
p [x].include?(x), [1, 2].include?(1), [x, 1].hash
class Array
  alias include? old_include?
  alias hash old_hash
end
p [x].include?(x), [x, 1].hash == [2, 1].hash

# A refinement of include? turns the fast path off where it is in use.
module R
  refine Array do
    def include?(v) = "refined #{v}"
  end
end
using R
p [x].include?(x), [1].include?(1)
