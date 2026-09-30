# A hash arriving as a poly value (nested, kwargs-splat, Marshal round-trip)
# must inspect through its hash-variant inspect helper, not as #<Object>.

# Nested hash literal: the inner hash is boxed as a poly value.
p({a: {b: 1}})

# Double-splat keyword capture returns a symbol-keyed hash.
def f(**k) = k
p f(x: 1)

# Rest + keyword splat: the hash rides inside a poly array.
def g(*a, **k) = [a, k]
p g(1, x: 2)

# Marshal round-trip builds a poly-poly hash at runtime.
p Marshal.load(Marshal.dump({a: 1, b: 2}))

# Route a hash receiver through a method param so the call is not
# constant-folded; the value is an opaque poly hash at the inspect site.
def show(h) = p(h)
show({k: {v: [1, 2]}, w: 3})

# String-keyed hashes (Integer values / String values) as values of another
# hash: inspect shows them as hashes.
def wrap(h) = {outer: h}
p wrap({"a" => 1, "b" => 2})
p wrap({"k" => "v"})
