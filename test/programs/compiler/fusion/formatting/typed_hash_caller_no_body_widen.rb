# A caller passes a hash with String keys and String values, and
# the callee reads it with `[]` in its body. The parameter keeps
# the type of the hash that the caller passes.
#
# The shape comes from a template engine: a method that gets the
# ivars hash of a request and reads keys out of it.

class Request
  attr_accessor :ivars
  def initialize
    @ivars = {"k" => "v"}
    @ivars.delete("k")
  end
end

def lookup_typed(h, key)
  h[key].to_s
end

def forward_to_typed(locals, ivars)
  out = ""
  out += lookup_typed(ivars, "name")
  out += "/"
  out += lookup_typed(ivars, "count")
  out += "/"
  out += ivars["raw"].to_s
  out
end

req = Request.new
req.ivars["name"] = "alice"
req.ivars["count"] = "5"
req.ivars["raw"] = "<i>I</i>"
puts forward_to_typed({"unused" => "x"}, req.ivars)
