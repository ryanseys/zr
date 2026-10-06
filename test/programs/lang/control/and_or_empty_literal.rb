# An empty `[]` / `{}` on the right of `&&` / `||` carries no element type of
# its own. The result is still the empty Array or Hash when the right side
# wins, whatever the type of the LEFT operand (true, an Integer, and so on).
def show(l, v); puts "#{l}: #{v.inspect}"; end

show("true && []",     true && [])
show("true && {}",     true && {})
show("false && []",    false && [])
show("1 && []",        1 && [])
show("'s' && []",      "s" && [])
show("nil && []",      nil && [])
show("true || []",     true || [])
show("nil || []",      nil || [])
show("false || []",    false || [])
show("1 || []",        1 || [])
show("nil || {}",      nil || {})

# a non-empty literal in the same position was never affected
show("true && [1]",    true && [1])
show("true && {1=>2}", true && {1 => 2})

# the value is a real container, not just one that prints right
r = true && []
r << 1
show("mutated", r)
h = true && {}
h["k"] = 1
show("hash mutated", h)
show("size", (true && []).size)
show("each", (true && []).each { |x| x })

# chains and method bodies reach the same emitter
show("chain", true && [] || ["x"])
show("nested", true && (false || []))
def f(flag); flag && []; end
show("m true", f(true))
show("m false", f(false))
def g(flag); flag || {}; end
show("g nil", g(nil))
show("g 1", g(1))
