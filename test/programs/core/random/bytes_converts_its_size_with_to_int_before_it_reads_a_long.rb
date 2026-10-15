# Random#bytes and Random.bytes convert the size with to_int first, so a
# non-finite Float raises FloatDomainError and a huge one is a Bignum
# that does not fit a long. Random.urandom reads the size as a long.
class Two
  def to_int = 2
  def inspect = "Two"
end

class Bad
  def to_int = "2"
  def inspect = "Bad"
end

sizes = [Float::INFINITY, -Float::INFINITY, Float::NAN, 1e30, -1e30, 2.9, -0.5, 0.0,
         2**64, -1, nil, "3", Two.new, Bad.new, Rational(5, 2)]
sizes.each do |size|
  results = [-> { Random.new(1).bytes(size) }, -> { Random.bytes(size) }, -> { Random.urandom(size) }].map do |call|
    bytes = call.call
    "#{bytes.class}(#{bytes.bytesize})"
  rescue => e
    "#{e.class}: #{e.message}"
  end
  puts "#{size.inspect}: #{results.join(' | ')}"
end
