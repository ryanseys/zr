# Hash#each on a receiver whose type is known only at run time
# runs the block for each pair. The block gets the pair as
# `|k, v|`.

module M
  def self.iter(hash)
    n = 0
    hash.each { |_k, _v| n += 1 }
    n
  end
end

# Two call sites pass different kinds of hash, so the param type is
# known only at run time. Both shapes iterate.
puts "a=#{M.iter({ a: 1, b: 2 })}"     # Symbol => Integer, expect 2
puts "b=#{M.iter({ "x" => "y" })}"     # String => String, expect 1

# Same surface with int-keyed hash + str values, an empty hash,
# and a single-pair String => Integer hash. The third call drives the
# per-iteration block param so we verify keys/values arrive.
def m3(h)
  out = ""
  h.each { |k, v| out += k.to_s + "=" + v.to_s + ";" }
  out
end

puts m3({1 => "one", 2 => "two"})        # Integer => String
puts m3({})                              # empty
puts m3({"k" => 42})                     # String => Integer
