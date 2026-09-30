# merge / dup / delete on a hash with Symbol keys and Integer
# values. The kwarg-shorthand form `h.merge(c: 3)` and the
# hash-argument form both work.
#
# roundhouse's `ActionView::ViewHelpers.link_to` builds an
# HTML-attrs hash via `.merge`, also with numeric values.

def merge_kwarg(h)
  h.merge(c: 3, d: 4)
end

def merge_hash(h)
  h.merge({c: 3, d: 4})
end

# Both forms.
r1 = merge_kwarg({a: 1, b: 2})
puts r1[:a]   # 1
puts r1[:b]   # 2
puts r1[:c]   # 3
puts r1[:d]   # 4

r2 = merge_hash({a: 10, b: 20})
puts r2[:a]   # 10
puts r2[:c]   # 3

# dup
h = {x: 100, y: 200}
h2 = h.dup
puts h2[:x]   # 100
puts h2[:y]   # 200

# delete
h3 = {p: 1, q: 2, r: 3}
h3.delete(:q)
puts h3[:p]   # 1
puts h3[:q]   # nil (missing now)
puts h3[:r]   # 3
