# Integer() raises for a String in an ASCII-incompatible encoding, also
# with exception: false. Rational() and Complex() take one or two
# arguments. catch with no block says "no block given". singleton_method
# takes a Symbol, a String or what to_str gives. Range#count and the
# const_ methods name the value they could not use.
def try(label)
  r = yield
  puts "#{label}: #{r.inspect}"
rescue StandardError => e
  puts "#{label}: #{e.class}: #{e.message}"
end

%w[UTF-16LE UTF-16BE UTF-32LE].each do |enc|
  try("Integer(#{enc})") { Integer("12".encode(enc)) }
  try("Integer(#{enc}, 10)") { Integer("12".encode(enc), 10) }
  try("Integer(#{enc}, exception: false)") { Integer("x".encode(enc), exception: false) }
  try("Float(#{enc})") { Float("1".encode(enc)) }
  try("Rational(#{enc})") { Rational("1".encode(enc)) }
  try("Complex(#{enc})") { Complex("1".encode(enc)) }
end
try("Integer(EUC-JP)") { Integer("12".encode("EUC-JP")) }
try("Integer(bad, exception: false)") { Integer("x", exception: false) }
try("Rational()") { Rational() }
try("Rational(1, 2, 3)") { Rational(1, 2, 3) }
try("Rational(1, 2)") { Rational(1, 2) }
try("Rational(exception: false)") { Rational(exception: false) }
try("Complex()") { Complex() }
try("Complex(1, 2, 3)") { Complex(1, 2, 3) }
try("Complex(1, 2)") { Complex(1, 2) }
try("catch") { catch }
try("catch(:x)") { catch(:x) }
try("catch {}") { catch { |tag| throw tag, 7 } }
def self.solo = :solo
try("singleton_method(:solo)") { singleton_method(:solo).call }
try("singleton_method('solo')") { singleton_method("solo").call }
try("singleton_method(to_str)") { singleton_method(Struct.new(:to_str).new("solo")).call }
try("singleton_method(1)") { singleton_method(1) }
try("singleton_method(nil)") { singleton_method(nil) }
try("singleton_method(:none)") { singleton_method(:none) }
(1..4).each do |n|
  try("(1..6).count(#{n} args)") { (1..6).count(*Array.new(n) { 2 }) }
end
try("(1..6).count(2)") { (1..6).count(2) }
[1, nil, 1.5].each do |v|
  try("const_get(#{v.inspect})") { Object.const_get(v) }
  try("const_defined?(#{v.inspect})") { Object.const_defined?(v) }
  try("const_source_location(#{v.inspect})") { Object.const_source_location(v) }
end
try("const_get(String)") { Object.const_get("String") }
