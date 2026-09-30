# Marshal.load with a proc: what the proc returns takes the place of each
# value, links too, and a symbol named again is not passed to it.
seen = []
tag = ->(v) { seen << v; v.is_a?(Integer) ? v * 10 : (v.is_a?(String) ? v.upcase : v) }
s = "x"
p Marshal.load(Marshal.dump([:a, :a, s, s, 1, [2], { k: 3 }, 1.5, nil, true, 2**70]), tag), seen
seen.clear
S = Struct.new(:a)
p Marshal.load(Marshal.dump([S.new(4), "é".encode("UTF-16LE"), /r/i, 1..2, Object]), tag).map(&:inspect), seen.map(&:class)
p Marshal.load(Marshal.dump("s"), proc { |v| v.is_a?(String) ? v.upcase : v })
p Marshal.load(Marshal.dump([1, 2]), ->(v) { v.is_a?(Array) ? :gone : v })
p Marshal.load(Marshal.dump("abc"), ->(v) { nil }), Marshal.load(Marshal.dump("abc"), ->(v) { v.frozen? }, freeze: true)
