# A length-like call (`size`) on a receiver of more than one class answers an
# Integer. One class answers it with an attr-reader of a Struct member that
# String#unpack1 filled (doom: `@file.read(entry.size)` on a WAD directory
# entry).
E = Struct.new(:offset, :size, :name)

class Box
  def initialize(n)
    @n = n
  end

  def bump!
    @n += 1
  end

  def size
    @n
  end
end

def lookup(arr, n)
  arr.find { |e| e.name == n }
end

meta = [4, "x"]
arr = [E.new(0, meta[0], "A"), "sentinel"]
entry = lookup(arr, "A")
if entry
  n = entry.size
  p n + 1
end

b = Box.new(3)
b.bump!
p b.size
