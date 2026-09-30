# User-defined instance_exec / instance_eval methods shadow the
# built-in ones. Ordinary method dispatch finds the user's method,
# as in CRuby.

class Wrap
  def initialize
    @marker = 0
  end

  # User-defined instance_exec on Wrap. The call site below calls this
  # method, as in CRuby.
  def instance_exec(x, &b)
    @marker = x + 100
    @marker
  end

  def marker
    @marker
  end
end

# Two instances of Wrap.
w1 = Wrap.new
w2 = Wrap.new
ret = w1.instance_exec(5) { |x| 9999 }  # block ignored -- user method runs
puts ret              # 105
puts w1.marker        # 105

# Sibling override of instance_eval. Same expected dispatch.
class Wrap2
  def initialize
    @tag = ""
  end

  def instance_eval(&b)
    @tag = "user-instance-eval-ran"
  end

  def tag
    @tag
  end
end

w3 = Wrap2.new
w4 = Wrap2.new
# Block body is a no-op -- the user method ignores it.
w3.instance_eval { 1 }   # block ignored by user method
puts w3.tag           # user-instance-eval-ran

puts "done"
