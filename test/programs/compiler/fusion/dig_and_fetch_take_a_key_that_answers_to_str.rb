class Sep
  def to_str
    "-"
  end
end

class Idx
  def to_int
    1
  end
end

def err
  yield
rescue StandardError => e
  [e.class, e.message]
end

s = String.new("a-b")
class Fmt
  def to_str
    "a"
  end
end
ENV["SPINEL_SLOT"] = "v"
class Key
  def to_str
    "SPINEL_SLOT"
  end
end
class Cmd
  def to_str
    "true"
  end
end

a = [1, 2, 3]
m = /(a)(b)/.match("ab")

h = { 1 => 2 }
p h.dig("a")
p h.dig(1.0)
p h.fetch("a", 9)
p h.except("a")
p h.slice("a", 1)
p h.values_at("a", 1)
p h.has_value?("x")
p h.has_value?(2.0)
p h.assoc("a")
p err { h.fetch("a") }
p err { h.fetch_values(1, :b) }
sh = { "a" => 1 }
p sh.assoc(2)
p sh.dig(:a)
p [1, 2].count("x")
p [1, 2].all?("x")
p [].all?("x")
p [1, 2].any?("x")
p [1, 2].none?("x")
p [1, 2].one?("x")
p [1, 2].delete("x")
p [1, 2].delete("x") { :none }
p ["a"].delete(1)
p [1, 2].index("x")
p [1, 2].rindex(:y)
p (1..2).include?("x")
p (1..2) === "x"
p (1..2).member?(nil)
p (1..2).eql?("x")
p (1..2).count("x")
p [1, 2.0].count(2)
p [1, 2].count(1.0)

