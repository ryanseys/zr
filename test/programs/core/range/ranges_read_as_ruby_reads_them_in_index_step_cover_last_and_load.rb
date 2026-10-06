# Array#[] and String#[] read any object that answers begin, end and
# exclude_end? as a Range. A beginless non-numeric range refuses to step.
# cover? of ends that do not compare is false. (nil..10).last(3) counts
# back from the end. A Range dumped before initialize loads as one.
def t(name)
  puts "#{name}: #{yield.inspect}"
rescue Exception => e
  puts "#{name}: #{e.class}: #{e.message.gsub(/0x\h+/, "0xADDR")}"
end
class DuckRange
  def initialize(b, e, excl = false) = (@begin, @end, @excl = b, e, excl)
  attr_reader :begin, :end
  def exclude_end? = @excl
end
t("string") { "abcd"[DuckRange.new(1, 2)] }
t("array") { [1, 2, 3, 4][DuckRange.new(1, 2, true)] }
o = Object.new
t("no begin") { [][o] }
class << o; attr_accessor :begin, :end end
o.begin = -10
o.end = 0
t("no exclude_end?") { [][o] }
def o.exclude_end? = false
t("index") { [0][o] }
t("set") { [0][o] = 1 }
class << o; private :begin, :end end
o.begin = 0
o.end = 10
t("private") { [0][o] }
t("beginless string step") { (...'aaa').step('a') }
t("beginless string step block") { (...'g').step(2) {} }
t("beginless symbol step") { (...:g).step(2) }
t("cover") { [(..2).cover?(.."2"), (..2).cover?(..2), (...2).cover?(..2)] }
t("last") { [(nil..10).last(3), (nil...10).last(3), (0..10).last(3), (8..10).last(5)] }
r = Marshal.load(Marshal.dump(Range.allocate))
t("load") { [r.frozen?, r.instance_eval { initialize(5, 6) }] }
t("endless cover") { [(2...).cover?(2..), (2..).cover?(2...), (2..).cover?(2..)] }
%i[to_i to_r to_f].each { |type| t("beginless step to_a #{type}") { (..10.send(type)).step(2.send(type)).to_a } }
class Range
  alias_method :plain_each, :each
  def each(&) = plain_each(&)
end
$each = 0
class Range
  def each(&b) = ($each += 1; plain_each(&b))
end
t("last with each") { [(0..10).last(3), $each] }
