# Inlined yield-bearing method bodies must (a) read ivars of the
# receiver, not of the call site, (b) use each of their own locals
# consistently, and (c) keep `raise X unless Y` inside the unless.

# A) Inlined `each` over an Integer-array ivar.
class C
  def initialize
    @nums = []
    @nums << 10
    @nums << 20
    @nums << 30
  end

  def each
    i = 0
    while i < @nums.length
      n = @nums[i]
      yield n
      i += 1
    end
    self
  end
end

c = C.new
c.each { |n| puts n.to_s }   # 10 / 20 / 30

# B) `raise X unless Y` inside an inlined yield-method body.
def measure
  before = 1
  yield
  after = 2
  raise "fail" unless after > before
  true
end

measure { puts "block" }      # block
puts "ok"                     # ok
