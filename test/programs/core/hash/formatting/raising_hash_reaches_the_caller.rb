# A user `hash` that raises is an ordinary exception, not a crash.
#
# The backtrace shape is the other half: `Hash#[]` and `Array#[]` are
# `opt_aref`, a VM instruction with no control frame, so ruby names the
# raising method and the caller and nothing between. `String#[]` is NOT
# specialized and keeps its frame.
class Boom
  def hash = raise("from hash")
  def eql?(_other) = true
end

h = { 1 => :one }
begin
  h[Boom.new]
rescue RuntimeError => e
  p [e.class.to_s, e.message, e.backtrace.first.include?("Hash#[]")]
end
begin
  h[Boom.new] = :two
rescue RuntimeError => e
  p e.message
end
begin
  [Boom.new].uniq
rescue RuntimeError => e
  p e.message
end
begin
  built = { Boom.new => 1 }
  p built
rescue RuntimeError => e
  p e.message
end
p h.size
