# Each inner top-level def has a per-test prefix, so its name is
# unique across the tests.


def t_kw_show(x: nil)
  puts x
end

def t_kw_nil_default_string_call
  t_kw_show(x: "hi")
  t_kw_show(x: nil)
end
t_kw_nil_default_string_call
