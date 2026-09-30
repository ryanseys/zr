# A local hash passed to a method whose param has another hash kind
# keeps its contents, also when the file has a begin/rescue.
#
# The shape: any begin/rescue in the file, a local with a typed-hash
# type, and a callee that expects a different hash kind.

def takes_str_poly(h)
  h.length
end

def trigger_setjmp
  begin
    raise "x"
  rescue
    1
  end
end

def build_and_call
  form_attrs = {a: "x", b: 1}    # Symbol keys, mixed values
  takes_str_poly(form_attrs)     # callee sees another hash kind
end

trigger_setjmp                    # the file has a begin/rescue
puts build_and_call
