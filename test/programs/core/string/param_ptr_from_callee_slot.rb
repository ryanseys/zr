# A method passes its param unchanged to another method. The param gets
# its type from the callee's use of it (here `length` on a String).
#
# Mirrors the Db.column_bool shape in real-blog: a thin wrapper
# around a typed primitive (FFI sqlite handle) that passes its
# `stmt` param to column_int.

module Box
  def self.read_int(p)
    p.length
  end

  def self.read_bool(p)
    read_int(p) != 0
  end
end

puts Box.read_int("abc")
puts Box.read_bool("abc")
puts Box.read_bool("")

# Same pattern across two layers — three-deep chain.
module Chain
  def self.head(s)
    middle(s)
  end

  def self.middle(s)
    tail(s)
  end

  def self.tail(s)
    s.length
  end
end

puts Chain.head("abc")
puts Chain.middle("xyz")
puts Chain.tail("hi")
