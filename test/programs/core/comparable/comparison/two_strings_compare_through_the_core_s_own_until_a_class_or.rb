p ["a" < "b", "b" <= "b", "c" > "b", "a" >= "b", "abc".between?("abb", "abd"), "z".clamp("a", "m")]
p ["\xff".b < "a", "é" > "e", "a".encode("UTF-16LE") >= "a"]
class Loud < String
  def <=>(other) = -(super)
end
p [Loud.new("a") < "b", "a" < Loud.new("b"), Loud.new("a").between?("b", "c")]
begin
  "a" < 1
rescue ArgumentError => e
  p e.message
end
module Backwards
  refine String do
    def <=>(other) = 0
  end
end
using Backwards
p ["a" < "b", "a" <=> "b"]
class String
  def <=>(other) = other.size <=> size
end
p ["a" < "bb", "bb" < "a", %w[x yyy zz].max]
