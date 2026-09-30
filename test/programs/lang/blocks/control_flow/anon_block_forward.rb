# Anonymous `&` block forwarding (Ruby 3.1+).
#
# `def outer(&); inner(&); end` declares an unnamed block parameter
# and forwards it via the matching anonymous `&` in the call. The
# unnamed parameter works like any other `&block`, and the bare `&`
# in the call forwards it.

# 1. Top-level outer/inner with anonymous & forwarding.
def outer(&)
  inner(&)
end

def inner(&block)
  block.call
end

outer { puts "1-top-level" }

# 2. Anonymous & with a body that does work before forwarding.
def with_prefix(label, &)
  puts label
  inner(&)
end

with_prefix("2-prefix") { puts "  body" }

# 3. Anonymous & on a class instance method, forwarding to another
#    class instance method via typed-receiver dispatch.
class Outer
  def kick(&)
    sink(&)
  end

  def sink(&block)
    block.call
  end
end

Outer.new.kick { puts "3-class-method" }
