# A Range walks anything with succ, an Integer toward a Float end too.
# Enumerable#uniq and Set#count take their blocks; collect names its own
# enumerator; with_index reads nil as 0. A Struct keeps a keyword Hash
# as a value when it has values by position too; one clamp argument
# must be a Range; Array() falls back to to_a; the set operators and
# Queue.new convert as CRuby does; ENV answers the Hash methods.
def t = yield rescue [$!.class, $!.message]

p t { (1...3.5).to_a }, t { (1..3.0).to_a }, t { (1.5..3).to_a }
Day = Struct.new(:n) do
  include Comparable
  def succ = Day.new(n + 1)
  def <=>(other) = n <=> other.n
end
p t { (Day.new(1)..Day.new(3)).map(&:n) }, t { (Day.new(1)...Day.new(3)).map(&:n) }, t { (:a..:c).to_a }, t { (:a..).first(2) }
p t { (1..6).uniq { _1 % 3 } }, t { [1, -1, 2].uniq!(&:abs) }, t { Set[1, 2, 3].count(&:odd?) }, t { Set[1, 2, 3].count(2) }, t { Set[1, 2].count }
p t { [1, 2].collect.inspect }, t { [1, 2].each.with_index(nil).to_a }, t { [5, 6].each.with_index(1.5).to_a }

S = Struct.new(:a, :b)
p t { S.new(1, b: 2).b }, t { S.new(a: 1, b: 2).b }, t { Struct.new(:a, keyword_init: false).new(a: 1).a }
p t { 5.clamp(3) }, t { 5.clamp(nil) }, t { 5.clamp(1..3) }, t { 5.clamp(1..) }

class ToAryNil
  def to_ary = nil
  def to_a = [:fallback]
end

class ToAryOne
  def to_ary = 1
end
p t { Array(ToAryNil.new) }, t { Array(ToAryOne.new) }, t { Array(nil) }, t { Array(1..2) }
p t { [1] - nil }, t { [1] - 1 }, t { [1] & nil }, t { [1] | nil }, t { [1, 2] - [2] }, t { [1].each_entry.drop(-1) }, t { [1].each_entry.drop(nil) }
p t { Queue.new(1..3).size }, t { Queue.new(5) }, t { Queue.new([1]).pop }

ENV["ZR_P9_A"] = "zr-p9-one"
ENV["ZR_P9_B"] = "zr-p9-two"
p t { ENV.value?("zr-p9-two") }, t { ENV.has_value?("nope") }, t { ENV.value?(1) }, t { ENV.invert["zr-p9-one"] }, t { ENV.except("ZR_P9_A").key?("ZR_P9_A") }
p t { ENV.reject! { false } }, t { ENV.select! { true } }, t { ENV.filter! { true } }, t { ENV.keep_if { true }.equal?(ENV) }
p t { ENV.delete_if { |k, _| k == "ZR_P9_B" }.equal?(ENV) }, t { ENV["ZR_P9_B"] }, t { ENV.reject! { |k, _| k == "ZR_P9_A" }.equal?(ENV) }, t { ENV["ZR_P9_A"] }
p t { ENV.rehash }, t { ENV.delete_if.class }, t { ENV.filter!.class }, t { ENV.replace({"A" => 1}) }

