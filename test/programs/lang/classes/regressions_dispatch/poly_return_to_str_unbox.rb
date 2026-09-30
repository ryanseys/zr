# A method returns `@hash[key] || ""`. A hit gives the String value.
# A missing key gives nil, which is falsy, so the method returns "".

class T_poly_return_to_str_unbox_C
  attr_reader :h
  def initialize
    @h = {}
    @h["a"] = "alpha"
    @h["b"] = "beta"
  end

  def get(key)
    @h[key] || ""
  end
end

c = T_poly_return_to_str_unbox_C.new
puts c.get("a")
puts c.get("b")
puts c.get("missing")
puts c.get("a").length
puts c.get("missing").length
