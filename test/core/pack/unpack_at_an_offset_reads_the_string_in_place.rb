# unpack and unpack1 with `offset:` read the receiver in place. `@` and
# `X` count from the String's start, not from the offset; a chunk is
# binary whatever the receiver's encoding.
def show(label)
  v = yield
  v = [v, v.encoding] if v.is_a?(String)
  puts "#{label}: #{v.inspect}"
rescue => e
  puts "#{label}: #{e.class}: #{e.message}"
end

str = "héllo wörld\x00tail".dup
show("a") { str.unpack1("a3", offset: 1) }
show("Z") { str.unpack("Z*Z*", offset: 7) }
show("A") { "ab  \0 cd".unpack("A5a*", offset: 1) }
show("@") { str.unpack("@2a2", offset: 3) }
show("@ past") { str.unpack("@20a", offset: 3) }
show("X") { str.unpack("a2X2a1", offset: 3) }
show("X to the start") { str.unpack("Xa", offset: 3) }
show("X past the start") { str.unpack("X4", offset: 3) }
show("x past") { str.unpack("x40", offset: 3) }
show("U") { str.unpack("U*", offset: 2) }
show("U inside a character") { str.unpack("U", offset: 2) }
show("m") { "xxaGVsbG8=".unpack1("m", offset: 2) }
show("C") { str.unpack("C*", offset: 14) }
show("n") { "\x00\x01\x02\x03".b.unpack("nn", offset: 1) }
show("q") { ("\x01" * 20).b.unpack("q*", offset: 3) }
show("H") { "\xAB\xCD\xEF".b.unpack1("H*", offset: 1) }
show("B") { "\xAB\xCD".b.unpack1("B*", offset: 1) }
show("w") { "\x00\x81\x01".b.unpack("w*", offset: 1) }
show("at the end") { str.unpack("a*", offset: str.bytesize) }
show("negative") { str.unpack("a", offset: -1) }
show("past the end") { str.unpack("a", offset: 100) }

class Sub < String
  def byteslice(*) = "nope"
  def getbyte(*) = 0
end
show("a subclass") { Sub.new("abcd").unpack("a2C", offset: 1) }
show("a block") { r = []; "abcd".unpack("C*", offset: 2) { |c| r << c }; r }

__END__
a: ["\xC3\xA9l", #<Encoding:BINARY (ASCII-8BIT)>]
Z: ["w\xC3\xB6rld", "tail"]
A: ["b", "cd"]
@: ["\xA9l"]
@ past: ArgumentError: @ outside of string
X: ["ll", "l"]
X to the start: ["\xA9"]
X past the start: ArgumentError: X outside of string
x past: ArgumentError: x outside of string
U: ArgumentError: malformed UTF-8 character
U inside a character: ArgumentError: malformed UTF-8 character
m: ["hello", #<Encoding:BINARY (ASCII-8BIT)>]
C: [116, 97, 105, 108]
n: [258, nil]
q: [72340172838076673, 72340172838076673]
H: ["cdef", #<Encoding:US-ASCII>]
B: ["11001101", #<Encoding:US-ASCII>]
w: [129]
at the end: [""]
negative: ArgumentError: offset can't be negative
past the end: ArgumentError: offset outside of string
a subclass: ["bc", 100]
a block: [99, 100]
