# A value of unknown type flowing into `String#<<` on a mutable String.
# The canonical shape: a module-level method that returns
# `@hash[k] || ""` over a heterogeneously-valued hash, so its return
# type is only known at run time. `io << M.get(:t)` appends the String.

module M
  @data = {}

  def self.set(k, v)
    @data[k] = v
  end

  def self.get(k)
    @data[k] || ""
  end
end

# Mixed value types make the hash values' type known only at run time.
M.set(:n, 42)
M.set(:t, "hello")

io = String.new
io << M.get(:t)
puts io                # hello

# Also exercise the expression-context << path via chained append.
io2 = String.new
(io2 << M.get(:t)) << M.get(:t)
puts io2               # hellohello
