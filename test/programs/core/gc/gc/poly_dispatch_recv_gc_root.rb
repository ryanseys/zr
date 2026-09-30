# The receiver of a call whose class is known only at run time must stay
# alive while its method runs. It can be the only live reference to the
# receiver. Each go/add below collects and then allocates before it reads
# an ivar, so a receiver that was freed would give a wrong value or crash.
class Holder
  def initialize(params = {})
    @params = params
  end

  def go
    GC.start                                   # frees the unrooted receiver
    junk = Array.new(64) { |j| Holder.new(k: [j]) }   # hands its slot out again
    (@params[:k] || []).length + junk.length - 64
  end

  def add(x)
    GC.start
    junk = Array.new(64) { |j| Holder.new(k: [j]) }
    (@params[:k] || []).length + x + junk.length - 64
  end
end

class Other
  def go
    0
  end

  def add(x)
    x
  end
end

def pick
  return Other.new if false  # gives the call site a union receiver type
  Holder.new(k: [1, 2, 3])
end

r = 0
i = 0
while i < 50
  r += pick.go               # receiver lives only as the dispatch temporary
  r += pick.add(10)          # same, through the with-args dispatch
  i += 1
end
puts "ok r=#{r}"
