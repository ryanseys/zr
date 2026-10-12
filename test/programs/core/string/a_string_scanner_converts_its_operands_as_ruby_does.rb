# StringScanner takes a String, or a value with to_str, and raises
# TypeError with ruby's own message for any other value, in new, string=
# and <<. new takes and drops a second argument, the old dup flag.
require "strscan"

def try(label)
  r = yield
  puts "#{label}: #{r.inspect}"
rescue StandardError => e
  puts "#{label}: #{e.class}: #{e.message}"
end

path = Struct.new(:to_str).new("xy")
[1, nil, :a, 1.5, path, "ab"].each do |v|
  try("new(#{v.inspect})") { StringScanner.new(v) }
  try("string = #{v.inspect}") { s = StringScanner.new("a"); s.string = v; s.string }
  try("<< #{v.inspect}") { s = StringScanner.new("a"); s << v; s.string }
end
try("new(a, 1)") { StringScanner.new("a", 1) }
try("new(a, true, fixed_anchor: true)") { StringScanner.new("a", true, fixed_anchor: true).fixed_anchor? }
try("new(a, 1, 2)") { StringScanner.new("a", 1, 2) }
try("new()") { StringScanner.new }
try("scan(1)") { StringScanner.new("ab").scan(1) }
try("scan_until(nil)") { StringScanner.new("ab").scan_until(nil) }
try("skip(:a)") { StringScanner.new("ab").skip(:a) }
try("pos = '1'") { StringScanner.new("ab").pos = "1" }
try("pos = 5") { StringScanner.new("ab").pos = 5 }
try("peek(-1)") { StringScanner.new("ab").peek(-1) }
try("peek('1')") { StringScanner.new("ab").peek("1") }
try("[nil]") { s = StringScanner.new("ab"); s.scan(/a/); s[nil] }
try("[:y]") { s = StringScanner.new("ab"); s.scan(/(?<x>a)/); s[:y] }
try("['y']") { s = StringScanner.new("ab"); s.scan(/(?<x>a)/); s["y"] }
try("[1.5]") { s = StringScanner.new("ab"); s.scan(/a/); s[1.5] }
try("unscan") { StringScanner.new("ab").unscan }
try("scan_integer(base: 3)") { StringScanner.new("ab").scan_integer(base: 3) }
try("pos = 1.5") { s = StringScanner.new("ab"); s.pos = 1.5; s.pos }
try("pos = nil") { StringScanner.new("ab").pos = nil }
try("peek(1.9)") { StringScanner.new("ab").peek(1.9) }
try("peek(nil)") { StringScanner.new("ab").peek(nil) }
try("[2**70]") { s = StringScanner.new("ab"); s.scan(/a/); s[2**70] }
try("['x']") { s = StringScanner.new("ab"); s.scan(/(?<x>a)/); s["x"] }
try("scan(to_str)") { StringScanner.new("ab").scan(Struct.new(:to_str).new("a")) }
try("check_until(1)") { StringScanner.new("ab").check_until(1) }
