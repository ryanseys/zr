# A Hash finds a key's code from its `hash` as rb_any_hash does: a
# bignum folds through its own hash, a Float converts with to_int, and any
# other value converts with to_int too, so nil, a String or a Symbol
# raises TypeError. A literal, []=, a lookup and a literal in an Array
# all raise the same.
$stdout.sync = true
class Code
  def initialize(code) = @code = code
  def hash = @code
  def eql?(other) = other.is_a?(Code)
end

class ToInt
  def to_int = 3
end

class BadToInt
  def to_int = "no"
end

[nil, "x", :s, [1], true, 1.5, 2.0**70, 2**70, -1, ToInt.new, BadToInt.new].each do |code|
  key = Code.new(code)
  results = [
    -> { {key => 1}.size },
    -> { h = {}; h[key] = 1; h.size },
    -> { {1 => 2}.key?(key) },
    -> { [key => 1].first.size },
    -> { [key].to_h { [_1, 1] }.size },
    -> { [key, Code.new(code)].uniq.size }
  ].map do |f|
    f.call
  rescue => e
    "#{e.class}: #{e.message}"
  end
  puts "#{code.class}: #{results.inspect}"
end
