# Index operator-assignment (`arr[i] += x`) on a captured variable inside a
# block that escapes into a Thread. The block is lifted to a real proc whose
# result is the value of the block, so the op-write appears in VALUE position.
# The compound form works as `arr[i] = arr[i] + x` does, and the expression's
# value is the stored result.

module P
  def self.each_index(n, nt, &blk)
    ws = []
    w = 0
    while w < nt
      ws << Thread.new(w) { |wid| i = wid; while i < n; blk.call(i); i += nt; end }
      w += 1
    end
    ws.each { |t| t.join }
  end
end

a = Array.new(4, 0.0)
P.each_index(4, 2) { |i| a[i] += 1.5 }
p a

# the expression's value is the stored (post-op) result, through a
# thread-escaping block whose call result is consumed
r = nil
b = [10]
t = Thread.new { r = b[0] += 7 }
t.join
p r
p b

# hash receiver in value position
h = { "k" => 10 }
f = proc { |k| h[k] += 5 }
p f.call("k")
p h
