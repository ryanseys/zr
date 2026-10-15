# Enumerable#count and #find_index take no argument or exactly one
# (rb_scan_args "1"), so a second or third argument says "expected
# 1". Array's own count and find_index say "expected 0..1".
def try(label)
  r = yield
  r = r.class if r.is_a?(Enumerator)
  puts "#{label}: #{r.inspect}"
rescue ArgumentError => e
  puts "#{label}: #{e.class}: #{e.message}"
end

class Bag
  include Enumerable

  def each
    yield 1
    yield 2
    yield 1
  end
end

h = { a: 1, b: 2 }
sources = { "Hash" => h, "Range" => (1..3), "Bag" => Bag.new, "Enumerator" => [1, 2, 1].each,
            "Struct" => Struct.new(:x, :y).new(1, 2), "Array" => [1, 2, 1] }
sources.each do |name, src|
  try("#{name}#count") { src.count }
  try("#{name}#count(1)") { src.count(1) }
  try("#{name}#count {}") { src.count { |x| x == 1 } }
  try("#{name}#count(1, 2)") { src.count(1, 2) }
  try("#{name}#count(1, 2) {}") { src.count(1, 2) { true } }
  try("#{name}#count(nil, nil)") { src.count(nil, nil) }
  try("#{name}#find_index") { src.find_index }
  try("#{name}#find_index(2)") { src.find_index(2) }
  try("#{name}#find_index {}") { src.find_index { |x| x == 2 } }
  try("#{name}#find_index(1, 2)") { src.find_index(1, 2) }
  try("#{name}#find_index(1, 2) {}") { src.find_index(1, 2) { true } }
  try("#{name}#find_index(1, 2, 3)") { src.find_index(1, 2, 3) }
  try("#{name}#find_index(1, 2, 3, 4) {}") { src.find_index(1, 2, 3, 4) { true } }
end
try("endless Range#count(1, 2)") { (1..).count(1, 2) }
try("send count") { h.public_send(:count, nil, 0) }
try("send find_index") { (0..4).public_send(:find_index, "", 0) }
try("send find_index, three") { (nil..nil).public_send(:find_index, :a, 1.5, "") }
