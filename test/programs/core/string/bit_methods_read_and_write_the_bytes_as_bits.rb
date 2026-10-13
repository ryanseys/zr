# ruby 4.1's String bit operations (Feature #22118) and Integer#bit_count
# (Feature #20163). Bits number from the least significant bit of each
# byte, or from the most with lsb_first: false. Reads clamp to the bits
# there are; writes raise for bits past the end.
def t(label)
  r = yield
  puts "#{label}: #{r.inspect}#{" #{r.encoding}" if r.is_a?(String)}"
rescue Exception => e
  puts "#{label}: #{e.class}: #{e.message}"
end
p [0, 1, 7, 0b10101, 255, 2**62 - 1, 2**64, 2**1000, 2**1000 - 1].map(&:bit_count)
t("neg") { -1.bit_count }
t("negbig") { (-2**70).bit_count }
s = "\x01\x80\xFF".b
t("get0") { s.bit_get(0) }
t("get7") { s.bit_get(7) }
t("get15") { s.bit_get(15) }
t("get15 msb") { s.bit_get(15, lsb_first: false) }
t("get8 msb") { s.bit_get(8, lsb_first: false) }
t("get24") { s.bit_get(24) }
t("get big") { s.bit_get(2**64 - 1) }
t("get bigger") { s.bit_get(2**64) }
t("get neg") { s.bit_get(-1) }
t("get negbig") { s.bit_get(-2**70) }
t("get float") { s.bit_get(1.9) }
t("get str") { s.bit_get("1") }
t("get nil") { s.bit_get(nil) }
t("get lsb nil") { s.bit_get(0, lsb_first: nil) }
t("get lsb 1") { s.bit_get(0, lsb_first: 1) }
t("get badkw") { s.bit_get(0, foo: 1) }
t("get 0 args") { s.bit_get }
t("get 2 args") { s.bit_get(1, 2) }
t("set? 0") { s.bit_set?(0) }
t("set? 1") { s.bit_set?(1) }
t("set? out") { s.bit_set?(99) }
t("utf8") { "é".bit_get(0) }
t("set") { x = "\x00\x00".b; [x.bit_set(3).equal?(x), x] }
t("set msb") { "\x00\x00".b.bit_set(3, lsb_first: false) }
t("clear") { "\xFF".b.bit_clear(1) }
t("flip") { "\x0F".b.bit_flip(7) }
t("set out") { "\x00".b.bit_set(8) }
t("set neg") { "\x00".b.bit_set(-1) }
t("set frozen") { "\x00".b.freeze.bit_set(0) }
t("set frozen out") { "\x00".b.freeze.bit_set(99) }
t("set len") { "\x00\x00\x00".b.bit_set(4, 12) }
t("set len msb") { "\x00\x00\x00".b.bit_set(4, 12, lsb_first: false) }
t("clear len") { "\xFF\xFF".b.bit_clear(3, 10) }
t("flip len") { "\x0F\xF0".b.bit_flip(0, 16) }
t("set len 0") { "\x00".b.bit_set(8, 0) }
t("set len 0 past") { "\x00".b.bit_set(9, 0) }
t("set len over") { "\x00".b.bit_set(4, 5) }
t("set len neg") { "\x00".b.bit_set(0, -1) }
t("set len nil") { "\x00".b.bit_set(0, nil) }
t("set range") { "\x00\x00".b.bit_set(2..9) }
t("set range excl") { "\x00\x00".b.bit_set(2...9) }
t("set range endless") { "\x00\x00".b.bit_set(12..) }
t("set range beginless") { "\x00\x00".b.bit_set(..3) }
t("set range empty") { "\x00\x00".b.bit_set(5...5) }
t("set range rev") { "\x00\x00".b.bit_set(5..2) }
t("set range over") { "\x00\x00".b.bit_set(10..16) }
t("set range start past") { "\x00\x00".b.bit_set(17..) }
t("set range len") { "\x00\x00".b.bit_set(1..2, 3) }
t("set range neg") { "\x00\x00".b.bit_set(-2..) }
t("set frozen len0") { "\x00".b.freeze.bit_set(0, 0) }
t("set utf8") { x = +"a"; x.bit_set(7); [x, x.valid_encoding?, x.encoding] }
t("set 3 args") { "\x00".b.bit_set(1, 2, 3) }
t("count") { "\xFF\x01".b.bit_count }
t("count empty") { "".bit_count }
t("count len") { "\xFF\xFF".b.bit_count(4, 6) }
t("count len msb") { "\x0F\xFF".b.bit_count(0, 4, lsb_first: false) }
t("count len clamp") { "\xFF".b.bit_count(4, 100) }
t("count past") { "\xFF".b.bit_count(8, 1) }
t("count 1 arg") { "\xFF".b.bit_count(1) }
t("count range") { "\xFF\xFF".b.bit_count(3..10) }
t("count range past") { "\xFF".b.bit_count(9..) }
t("count range end") { "\xFF".b.bit_count(8..) }
t("count range len") { "\xFF".b.bit_count(1..2, 3) }
t("count lsb bad") { "\xFF".b.bit_count(lsb_first: 3) }
t("count 3") { "\xFF".b.bit_count(1, 2, 3) }
t("count neg len") { "\xFF".b.bit_count(0, -1) }
t("count big len") { "\xFF".b.bit_count(0, 2**64) }
t("not") { "\x0F\xF0".b.bitwise_not }
t("not utf8") { r = "ab".bitwise_not; [r, r.encoding, r.frozen?] }
t("not!") { x = +"\x0F"; [x.bitwise_not!.equal?(x), x, x.encoding] }
t("not! frozen") { "a".freeze.bitwise_not! }
t("and") { "\x0F\xFF".b.bitwise_and("\xFF\x0F".b) }
t("or") { "\x0F\x00".b.bitwise_or("\xF0\x00".b) }
t("xor") { "\xFF\x00".b.bitwise_xor("\x0F\x0F".b) }
t("and len") { "ab".bitwise_and("a") }
t("and type") { "ab".bitwise_and(1) }
t("and utf8") { r = "ab".bitwise_and("cd"); [r, r.encoding] }
t("or!") { x = +"ab"; [x.bitwise_or!("  ").equal?(x), x, x.encoding] }
t("xor! frozen") { "ab".freeze.bitwise_xor!("cd") }
t("xor! len frozen") { "ab".freeze.bitwise_xor!("c") }
t("xor! to_str") { o = Object.new; def o.to_str = "\x01\x01"; (+"ab").bitwise_xor!(o) }
class MyS < String; end
t("subclass") { MyS.new("ab").bitwise_not.class }
p %i[bit_get bit_set? bit_set bit_clear bit_flip bit_count bitwise_not bitwise_not! bitwise_and bitwise_and! bitwise_or bitwise_xor!].map { |m| String.instance_method(m).arity }
p String.instance_method(:bit_get).parameters, Integer.instance_method(:bit_count).arity

# A seeded sweep over regions and both bit orders.
r = Random.new(22118)
sums = []
40.times do
  s = Array.new(r.rand(1..9)) { r.rand(256) }.pack("C*")
  bits = s.bytesize * 8
  beg = r.rand(0..bits)
  len = r.rand(0..(bits - beg))
  lsb = r.rand(2) == 0
  x = s.dup
  y = s.dup
  z = s.dup
  sums << [s.bit_count(beg, len, lsb_first: lsb), s.bit_count(beg...(beg + len), lsb_first: lsb),
           x.bit_set(beg, len, lsb_first: lsb), y.bit_clear(beg..(beg + len - 1), lsb_first: lsb),
           z.bit_flip(beg, len, lsb_first: lsb), (beg < bits ? s.bit_get(beg, lsb_first: lsb) : nil),
           s.bitwise_xor(x), s.bitwise_and(y).bitwise_or(z).bitwise_not]
end
sums.each { |row| p row }
big = ("\xA5".b * 100_000)
p big.bit_count, big.bit_count(3, 700_000), big.dup.bit_flip(0, 800_000).bit_count
