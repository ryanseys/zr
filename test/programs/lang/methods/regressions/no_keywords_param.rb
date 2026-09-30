# Each inner top-level def has a per-test prefix, so its name is
# unique across the tests.


def t_nkp_add(a, b, **nil)
  a + b
end

def t_no_keywords_param
  puts t_nkp_add(1, 2)
  puts t_nkp_add(10, 20)
end
t_no_keywords_param
