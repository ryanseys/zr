# Under a TracePoint each operator that ruby optimizes fires its
# :c_call and :c_return, and != fires the == that it calls.
[:c_call, :c_return].each do |type|
  methods = []
  tp = TracePoint.new(type) { |tp| methods << tp.method_id }
  tp.enable do
    x = "a"; x = -x
    [1].max
    [1].min
    x = 42 + 2
    x = 42 - 2
    x = 42 * 2
    x = 42 / 2
    x = 42 % 2
    y = x == 42
    y = x < 42
    y = x <= 42
    y = x > 42
    y = x >= 42
    x = x << 1
    x = x & 1
    x = x | 1
    x = []; x[1]
    x[1] = 2
    x.length
    x.empty?
    x.nil?
    x = 1; x.succ
    !x
    x = 'a'; x =~ /a/
    x = y
  end
  p methods
end
methods = []
tp = TracePoint.new(:c_call, :c_return) { |tp| methods << tp.method_id }
tp.enable do
  x = 1
  x != 42
end
p methods

# A program's == runs under != with :call and :return; a regexp literal
# that compiles the first time it runs fires nothing of its own.
class Money
  def initialize(n) = (@n = n)
  attr_reader :n
  def ==(other) = other.is_a?(Money) && n == other.n
end
events = []
tp = TracePoint.new(:call, :return, :c_call, :c_return) { |t| events << [t.event, t.method_id] }
a = Money.new(1)
tp.enable do
  a != Money.new(2)
  "abc" =~ /b(c)/
  [1, 2].include?(2)
end
events.each { |e| p e }
