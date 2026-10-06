# `&proc_var` argument forwarding (`def m(&b); g(&b); end`).
#
# `&expr` in call argument position (`g(&block)`) passes the proc as
# the block of the call, at every forwarding call site. It is not a
# positional argument. The rows cover a self call (Site A), a call on
# a typed receiver (Site B) and a receiverless call.

# 1. Site A (self-call) &proc_var forwarding.
class Forwarder
  def outer(&block)
    inner(&block)
  end

  def inner(&block)
    block.call
  end
end

Forwarder.new.outer { puts "1-self-amp" }

# 2. Site B (typed-receiver) &proc_var forwarding — outer captures
#    &block, then forwards it to a different receiver's method.
class Sink
  def receive(&block)
    block.call
  end
end

class Source
  def relay(sink, &block)
    sink.receive(&block)
  end
end

Source.new.relay(Sink.new) { puts "2-recv-amp" }

# 3. Top-level (receiverless) `&proc_var` forwarding.
def outer_top(&block)
  inner_top(&block)
end

def inner_top(&block)
  block.call
end

outer_top { puts "3-top-amp" }

puts "done"
