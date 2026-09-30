# A Hash param that the method only reads with `each do |k, v|`. A
# formatter that iterates the hash, like this
# `Tep::Json.encode_object` shape:
#
#   def self.encode(h)
#     out = ""
#     h.each do |k, v|
#       out = out + k + "=" + v
#     end
#     out
#   end
#
# concatenates each String key and value into the result.
#
# The test exercises two shapes:
#   - module class method with String-to-String hash inputs at two
#     differently-keyed call sites (the Tep shape),
#   - class instance method with the same body shape.

module Joiner
  def self.encode(h)
    out = ""
    first = true
    h.each do |k, v|
      if !first
        out = out + ","
      end
      first = false
      out = out + k + "=" + v
    end
    out
  end
end

puts Joiner.encode({"a" => "1", "b" => "2"})    # a=1,b=2
puts Joiner.encode({"x" => "y"})                # x=y

class Cookie
  def serialize(opts)
    out = ""
    first = true
    opts.each do |k, v|
      if !first
        out = out + ";"
      end
      first = false
      out = out + k + "=" + v
    end
    out
  end
end

c = Cookie.new
puts c.serialize({"path" => "/", "domain" => "example.com"})
