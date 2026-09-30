# A method param that holds a Hash with String keys and values, where
# the body iterates it with `pname.each do |k, v|`. This is the usual
# string-keyed-Hash shape in Rails/Tep-like code.

# Shape 1: the body concatenates `+ k + "=" + v` into `out`, so
# both k and v are Strings.
module Joiner
  def self.encode(h)
    out = ""
    first = true
    h.each do |k, v|
      if !first
        out = out + ","
      end
      first = false
      out = out + k + "=" + v
    end
    out
  end
end

puts Joiner.encode({"a" => "1", "b" => "2"})    # a=1,b=2

# Shape 2: no concatenation, just each|k,v|. The body pushes each k
# and v into an ivar array.
class HashDumper
  def initialize
    @pairs = []
  end
  attr_reader :pairs

  def collect(h)
    h.each do |k, v|
      @pairs << k
      @pairs << v
    end
  end
end

d = HashDumper.new
d.collect({"name" => "ada", "role" => "engineer"})
puts d.pairs.length.to_s   # 4
puts d.pairs[0]            # name
puts d.pairs[1]            # ada
puts d.pairs[2]            # role
puts d.pairs[3]            # engineer
