# `sub.fetch(k, d)` where sub came from a lookup in a hash with String
# keys and mixed values. At run time sub is a Hash, so Hash#fetch does
# the lookup and does not answer the default.
#
# A user-defined class with a `fetch` method makes the call site able
# to reach either class.

class FlashLike
  def fetch(key, default)
    "from-flash"
  end
end

# Keep FlashLike#fetch alive so the user-class arm is emitted.
puts FlashLike.new.fetch("x", "y")

def get_raw(h)
  h["x"]
end

def lookup(h)
  sub = get_raw(h)
  sub.fetch("title", "DEFAULT")
end

puts lookup({ "x" => { "title" => "real" } })
