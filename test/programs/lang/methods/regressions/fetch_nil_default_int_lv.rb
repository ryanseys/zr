# Each inner top-level def has a per-test prefix, so its name is
# unique across the tests.


def t_fndi_f(opts = {})
  v = opts.fetch(:k, nil)
  v.nil? ? "missing" : "found"
end

def t_fetch_nil_default_int_lv
  puts t_fndi_f
end
t_fetch_nil_default_int_lv
