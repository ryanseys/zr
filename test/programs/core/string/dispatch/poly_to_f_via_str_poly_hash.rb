# `.to_f` on a String value whose type is only known at run time parses
# the number, the same as on a receiver that is statically a String.
#
# Shape from a JSON-ish Hash[String, untyped]: read a string
# value out of a heterogeneous hash and call .to_f on it.

class C
  def initialize
    @h = { "w" => "900", "h" => "600.5", "pad" => " 2.5", "junk" => "abc", "blank" => "", "n" => 7, "f" => 1.25 }
  end

  def at(k)
    (@h[k]).to_f
  end
end

c = C.new
puts c.at("w")
puts c.at("h")
puts c.at("pad")
puts c.at("junk")
puts c.at("blank")
puts c.at("n")
puts c.at("f")
