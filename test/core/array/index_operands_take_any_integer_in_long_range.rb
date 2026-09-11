# An index or a size reads as NUM2LONG reads it: any Integer that fits a
# signed 64-bit word, a fixnum or not, and CRuby's RangeError past one. A
# length past the end reads to the end, and an index past either end
# names nothing; a Float truncates, and nil is refused.
def t = yield rescue [$!.class, $!.message]

a = [1, 2, 3]
p t { a[1, 2**62] }, t { a[1, 2**63 - 1] }, t { a[1, 2**63] }, t { a[2**62] }, t { a[-(2**62), 1] }
p t { a.first(2**62) }, t { a.last(2**62) }, t { a.rotate(2**62) }, t { a.sample(2**62).size }, t { a.take(2**62) }, t { a.drop(2**62) }
p t { "abc"[1, 2**62] }, t { "abc".byteslice(1, 2**63 - 1) }, t { "abc"[1, 2**63] }, t { "abc"[2**62, 1] }, t { "abc".byteslice(1.9, 1) }
p t { Array.new(2**62) }, t { Array.new(2**63) }, t { Array.new(2.7) }, t { Array.new(nil) }, t { a.first(2.5) }, t { a[1, 1.9] }, t { a.fetch(2**62) }
p t { a.values_at(2**62) }, t { a.dig(2**62) }, t { a.dup.insert(2**62, 1) }, t { [].fill(0, 2**62, 0) }, t { [].fill(0, 2**62, -1) }
p t { a.dup.tap { |b| b[2**62, 0] = 1 } }, t { a.dup.tap { |b| b[1, 2**62] = 9 } }, t { IO.new(2**40) }

list = Class.new { def to_ary = [:x, :y] }
p t { Array.new(list.new) }

__END__
[2, 3]
[2, 3]
[RangeError, "bignum too big to convert into 'long'"]
nil
nil
[1, 2, 3]
[1, 2, 3]
[2, 3, 1]
3
[1, 2, 3]
[]
"bc"
"bc"
[RangeError, "bignum too big to convert into 'long'"]
nil
"b"
[ArgumentError, "array size too big"]
[RangeError, "bignum too big to convert into 'long'"]
[nil, nil]
[TypeError, "no implicit conversion from nil to integer"]
[1, 2]
[2]
[IndexError, "index 4611686018427387904 outside of array bounds: -3...3"]
[nil]
nil
[IndexError, "index 4611686018427387904 too big"]
[ArgumentError, "argument too big"]
[]
[IndexError, "index 4611686018427387904 too big"]
[1, 9]
[RangeError, "integer 1099511627776 too big to convert to 'int'"]
[:x, :y]
