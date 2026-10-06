# Array#pack reads the Array as each element's conversion leaves it, a
# count too big for a C long is a RangeError, and unpack with a block
# yields no nil for a value that the bytes run out before.
def t(name)
  r = yield
  puts "#{name}: #{r.inspect}"
rescue => e
  puts "#{name}: #{e.class}: #{e.message}"
end

ary = []
obj = Object.new
obj.define_singleton_method(:to_str) do
  ary.clear
  "TALOS"
end
ary.push(obj, ".")
t("array emptied by to_str") { ary.pack("AA") }

t("pack count too big") { [].pack("C100000000000000000000") }
t("pack @ too big") { [].pack("@#{2**64}") }
t("unpack @ too big") { "0123456789".unpack("@#{2**64 - 100}C10") }
t("unpack @ outside") { "\x00".unpack("@2C") }

result = :ok
t("short with block") { "".unpack("i") { |x| result = x } }
p result
seen = []
t("partly short with block") { "\x01\x00\x00\x00".unpack("i2") { |x| seen << x } }
p seen
t("short without block") { "".unpack("i2d") }
t("floats with block") { [1.5].pack("d").unpack("d2") { |x| seen << x } }
p seen
