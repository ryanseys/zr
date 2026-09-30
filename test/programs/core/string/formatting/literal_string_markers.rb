# Strings that the runtime returns (class names, the inspect fallbacks, an
# exception with no object behind it) must stay valid across a collection.
# Each value below is held in a live local across an explicit GC.start.

def churn
  a = []
  200.times { |i| a.push("filler #{i}") }
  a.length
end

def through_gc(s)
  churn
  GC.start
  churn
  GC.start
  s
end

require "stringio"

p through_gc(StringIO.new("x").class.to_s)
p through_gc($stdout.class.to_s)
p through_gc(proc { 1 }.inspect).start_with?("#<Proc")
p through_gc([1, 2].each.inspect).start_with?("#<Enumerator")
p through_gc(:sym.inspect)
p through_gc(1.method(:+).inspect).start_with?("#<Method")

begin
  raise "boom"
rescue => e
  p through_gc(e.class.to_s)
  p through_gc(e.message)
end

# a nil Symbol slot
class Holder
  def initialize(s)
    @s = s
  end

  def label
    @s
  end
end
p through_gc(Holder.new(nil).label.to_s).length
p through_gc(:named.to_s)

# $0 is argv[0], which lives in the process's argument block rather than the
# string heap; it is an ordinary Ruby String all the same
p through_gc($0).class.to_s
p through_gc($PROGRAM_NAME).length > 0
