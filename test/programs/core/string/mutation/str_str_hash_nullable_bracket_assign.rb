# `h[k] = v` on a String-keyed hash that can be nil stores the value.
# This holds for String and Integer values. A request dispatcher
# builds a merged hash from a dup of the path params (the source
# ivar can be nil) and then writes into it inside a `.each` block.

class HashHolder
  def initialize
    @h = nil
  end

  attr_accessor :h
end

def fill(holder)
  # Force the slot's static type to `str_str_hash?` by routing the
  # initial value through a method that returns the nullable shape.
  holder.h = path_params
  holder.h["c"] = "3"
  holder.h["d"] = "4"
end

def path_params
  { "a" => "1", "b" => "2" }
end

hh = HashHolder.new
fill(hh)
m = hh.h
puts m["a"]   # 1
puts m["b"]   # 2
puts m["c"]   # 3
puts m["d"]   # 4
puts m.length # 4
