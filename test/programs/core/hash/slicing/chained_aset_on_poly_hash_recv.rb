# `outer[k1][k2] = v` where the values of `outer` can be of any type.
# There is no `is_a?(Hash)` check, so the inner `[]=` can go to a Hash
# as well as to an Array. Here the inner receiver is a Hash and the
# index is a String.
#
# This is the shape of a form decoder: `into[outer][inner] = val`.

def assign(into)
  into["x"]["y"] = "z"
  into["x"]["y"]
end

box = { "x" => { "y" => "old" } }
puts assign(box)
