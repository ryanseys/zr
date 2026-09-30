# Each inner top-level def has a per-test prefix, so its name is
# unique across the tests.


def t_porv_pick(a, b)
  a || b
end

def t_porv_pick_int(a, b)
  a || b
end

def t_poly_or_returns_value
  puts t_porv_pick(nil, "fallback")
  puts t_porv_pick("actual", "fallback")
  puts t_porv_pick_int(0, 5)
  puts(nil || "direct")
end
t_poly_or_returns_value
