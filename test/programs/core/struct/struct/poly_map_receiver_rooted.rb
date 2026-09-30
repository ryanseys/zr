# The receiver of a map loop is what the loop reads from, and the body
# allocates. A receiver built on the spot must stay alive while a
# collection runs inside the loop.
S = Struct.new(:x, :y)
g = (0...40).map { |i| S.new(i * 1.5, i * 2.5) }

total = 0.0
count = 0
g.each do |vertex|
  (g - [vertex]).map do |v|
    p v.x if count.zero?
    count += 1
    total += (v.x - vertex.x).abs
  end
end
p count
p total.round(3)

# the same shape with a hash receiver built on the spot
h = { a: 1, b: 2, c: 3 }
p (h.reject { |k, _| k == :b }).map { |k, v| "#{k}#{v}" }
