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
p [a.slice!(Idx.new, Idx.new), a]
p 8[Idx.new]
p 1 << Idx.new
p 8 >> Idx.new
p Time.at(Idx.new).to_i
p Time.utc(2000, Idx.new, Idx.new).month
p Time.local(2000, Idx.new, Idx.new).day
p Random.new(1).rand(Idx.new).class
p Random.rand(Idx.new).class
p [1, 2].each_slice(Idx.new).to_a
p [[1, 2], 3].dig(Idx.new)
m = /(a)(b)/.match("ab")
p [m.begin(Idx.new), m.end(Idx.new), m.offset(Idx.new), m.byteoffset(Idx.new), m.values_at(Idx.new)]
p /a/.match?("ba", Idx.new)
p err { [1, 2].cycle("x") { } }
p err { Random.rand("x") }
p err { a.slice!("x", 1) }
p err { 8["x"] }
p err { [1, 2].each_slice("x") { }; :no }
p err { Time.at([1]) }
p err { File.utime("x", "x", "nope") }
p err { 1.0.quo("x") }
p err { Math.sqrt("x") }
p err { Math.sqrt(nil) }
p err { Math.sqrt(Sep.new) }

