# Each inner top-level def has a per-test prefix, so its name is
# unique across the tests.


def t_pbia_kind_of(a)
  a.nil? ? "nil" : "something"
end

def t_poly_box_int_array
  puts t_pbia_kind_of(Object.new)
  puts t_pbia_kind_of([1, 2, 3])
end
t_poly_box_int_array
