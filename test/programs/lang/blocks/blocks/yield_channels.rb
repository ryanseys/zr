# frozen_string_literal: true

# The three channels a call carries -- positionals, keywords and the
# block -- reaching a `yield`, and the anonymous spellings of each,
# which ruby names `*`, `**` and `&`.

# `yield(*a)`: how many values reach the block is a run-time fact.
def spread(arr)
  yield(*arr)
end
spread([1, 2]) { |a, b| p [a, b] }
spread([]) { |a| p a }

# Keywords written at the yield. A block with no keyword parameters
# takes them as a trailing Hash.
def keyed
  yield 1, a: 2, b: 3
end
keyed { |x, opts| p [x, opts] }
keyed { |x, a:, b:| p [x, a, b] }

# A `**h` that is empty when it runs contributes nothing, so the block
# sees one fewer argument rather than a `{}`.
def double_splat(h)
  yield 9, **h
end
double_splat({ z: 1 }) { |x, **o| p [x, o] }
double_splat({}) { |x, *rest| p [x, rest] }

# The anonymous parameters, forwarded by name-less `*`, `**` and `&`.
def sink(*a, **k) = p [a, k]
def rest_only(*) = sink(*)
def kw_only(**) = sink(**)
def all_three(*, **, &) = sink(*, **, &)
rest_only(1, 2)
kw_only(a: 1)
all_three(1, b: 2)

def calls_block = yield 7
def forward(&) = calls_block(&)
p(forward { |x| x * 2 })

# An `|a, |` trailing comma binds nothing, but it does turn the block's
# auto-splat on, and it is not in the signature.
p proc { |a,| a }.parameters
p [[1, 2, 3]].map { |a,| a }
p [[1, 2, 3]].map { |a| a }

# ruby names each anonymous channel after the sigil that wrote it.
def anon_rest(*); end
def anon_kwrest(**); end
def anon_block(&); end
def forwards_all(...); end
p method(:anon_rest).parameters
p method(:anon_kwrest).parameters
p method(:anon_block).parameters
p method(:forwards_all).parameters
