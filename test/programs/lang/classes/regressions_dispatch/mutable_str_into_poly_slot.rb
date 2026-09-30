# A view method returns a String built with `String.new` and `<<`.
# It goes into a `body` attr, and another class writes an Integer to
# its own `body`. The String keeps its content, so `inspect` gives
# the quoted String. Roundhouse's Tep::Server#write_response reads a
# body in this way to write an HTTP response.

class T_mutable_str_into_poly_slot_View
  def self.index
    s = String.new
    s << "<h1>title</h1>"
    s << "<p>body</p>"
    s
  end
end

class T_mutable_str_into_poly_slot_Resp
  attr_accessor :body
  def initialize; @body = ""; end
end

class T_mutable_str_into_poly_slot_OtherResp
  attr_accessor :body
  def initialize; @body = 42; end  # an Integer body in another class
end

r = T_mutable_str_into_poly_slot_Resp.new
r.body = T_mutable_str_into_poly_slot_View.index
# inspect returns the quoted String.
puts r.body.inspect

# Use T_mutable_str_into_poly_slot_OtherResp too, so the program has both
# Integer and String bodies. The String body still works.
o = T_mutable_str_into_poly_slot_OtherResp.new
puts o.body.inspect

r2 = T_mutable_str_into_poly_slot_Resp.new
r2.body = T_mutable_str_into_poly_slot_View.index
puts r2.body.inspect
