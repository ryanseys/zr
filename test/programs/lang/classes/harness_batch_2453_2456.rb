# An array literal in argument position (Math.log([..].max, b)) gives its
# value to the call.
class S
  def initialize(score); @score = score; end
  def order; Math.log([(@score + 1).abs + 2, 1].max, 10); end
end
puts S.new(5).order.round(3)

# A user module named Random (OpenSSL::Random) does not clash with ::Random.
module OpenSSL
  module Random
    def self.random_bytes(n)
      out = ""
      i = 0
      while i < n
        # 1..127 (single-byte ASCII, never 0): this test exercises module
        # reopening + dispatch, not binary strings. A 128..255 byte can form a
        # multi-byte UTF-8 run and change #length. ASCII stays one byte == one
        # char, so #length is deterministic.
        out = out + (rand(127) + 1).chr
        i += 1
      end
      out
    end
  end
end
puts OpenSSL::Random.random_bytes(4).length

# Time minus a value of unknown type (holding a Time) is a Float duration.
class A2
  def stamp; "2020-01-01"; end
end
class B2
  def stamp; Time.at(0).utc; end
end
def time_ago(time); (Time.now.utc - time).to_i > 0; end
def show(x); time_ago(x.stamp); end
puts show(B2.new)
puts (show(A2.new) rescue "raised")
