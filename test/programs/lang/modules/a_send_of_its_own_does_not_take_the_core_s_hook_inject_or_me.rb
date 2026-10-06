# A module or an object with a `send` of its own: the core's own calls
# of a hook, of inject's operator and of a struct member's writer go by
# name, as rb_funcall goes, and never through it.
module Mixed
  def self.send(*) = raise("Mixed.send")
  def self.included(base) = (puts "included in #{base}")
end
class Host
  include Mixed
end
class Acc
  attr_reader :n
  def initialize(n) = @n = n
  def send(*) = raise("Acc#send")
  def +(other) = Acc.new(n + other)
end
p [1, 2, 3].inject(Acc.new(0), :+).n
p [Acc.new(1), 2, 3].inject(:+).n
S = Struct.new(:a) do
  def send(*) = raise("S#send")
end
p Marshal.load(Marshal.dump(S.new(4))).a
