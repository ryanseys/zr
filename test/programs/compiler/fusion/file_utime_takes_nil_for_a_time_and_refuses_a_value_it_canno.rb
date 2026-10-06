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

class Inert
end

def trace(label, value)
  puts label
  value
end

path = "/tmp/spinel_typed_slot_conversion.txt"
File.write(path, "x")
p File.utime(nil, nil, path)
File.delete(path)
p Time.utc(2000, 5, nil)
p Time.utc(2000, 5, 6, nil, nil, nil).min
p err { Random.rand(nil) }
p err { 1.0.quo(nil) }
p err { 1.0.quo(:s) }
p err { 7.0.fdiv(Sep.new) }
p err { 7.fdiv("x") }
p "a1b2c".split(/\d/) { |x| p x }
p err { "a b".split(true) }

