# Ruby's implicit-conversion protocols: `&obj` converts through `to_proc`,
# `**obj` through `to_hash`, and a splice/auto-splat value through `to_ary`.
# Each is duck-typed -- any object answering the method participates.

# --- **obj -> to_hash ------------------------------------------------------

class Opts
  def to_hash = { a: 1, b: 2 }
end

def take(a:, b:) = [a, b]
p take(**Opts.new)

# Into a keyword-rest callee.
def collect(**o) = o
p collect(**Opts.new)

# An explicit keyword alongside the converted splat.
p collect(x: 9, **Opts.new)

# A later key wins, matching Hash#merge order.
p collect(a: 99, **Opts.new)

# A converter held in a local.
o = Opts.new
p take(**o)

# A plain Hash splats without any conversion.
h = { a: 5, b: 6 }
p take(**h)
p collect(c: 7, **h)

# An object with no to_hash is a TypeError.
class NoHash; end
begin
  collect(**NoHash.new)
rescue TypeError => e
  puts "TypeError: #{e.message}"
end

