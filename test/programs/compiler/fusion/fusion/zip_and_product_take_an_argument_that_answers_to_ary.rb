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
sh = { "a" => 1 }


class Pair
  def to_ary
    [1, 2]
  end
end

class Tbl
  def to_hash
    { "b" => 2 }
  end
end

class Pair
  def to_ary
    [1, 2]
  end
end

class Tbl
  def to_hash
    { "b" => 2 }
  end
end

class Inert
end
p [3, 4].zip(Pair.new)
p [3, 4].product(Pair.new)
p({ "a" => 1 }.merge(Tbl.new))
p err { [1].zip(5) }
p err { [1].zip(nil) }
p err { [1].zip(Inert.new) }
p err { [1].product("x") }
p err { { "a" => 1 }.merge(5) }
p err { { "a" => 1 }.merge(Inert.new) }
p({ "a" => 1 }[Sep.new])

