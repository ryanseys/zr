# A name that names no encoding goes to the converter search as a C
# string: its bytes up to the first NUL, shown in the error as BINARY. A
# name in a wide encoding is no name, so "é" in UTF-16LE is the one byte
# 0xE9. A NUL inside a name is an ArgumentError; Encoding.find and
# force_encoding say "invalid encoding name (NUL byte)". An empty name
# leaves its side out of the message, and two unknown names that differ
# only in case are no conversion.
def try(label)
  r = yield
  r = [r, r.encoding] if r.is_a?(String)
  puts "#{label}: #{r.inspect}"
rescue StandardError => e
  puts "#{label}: #{e.class}: #{e.message.inspect}"
end

wide = "é".encode("UTF-16LE")
names = [wide, "é".encode("UTF-16BE"), "\xFF".b, "é", "UTF-8\0", "a\0".encode("UTF-16LE"), "", "nope", "x\0y", Encoding::UTF_8, "utf-8"]
names.each do |n|
  try("encode(#{n.inspect})") { "aaa".encode(n) }
  try("encode(#{n.inspect}, UTF-8)") { "aaa".encode(n, "UTF-8") }
  try("encode(UTF-8, #{n.inspect})") { "aaa".encode("UTF-8", n) }
  try("encode(#{n.inspect}, nope)") { "aaa".encode(n, "nope") }
  try("Converter.new(#{n.inspect}, UTF-8)") { Encoding::Converter.new(n, "UTF-8").class }
  try("Converter.new(UTF-8, #{n.inspect})") { Encoding::Converter.new("UTF-8", n).class }
  try("Encoding.find(#{n.inspect})") { Encoding.find(n) }
  try("force_encoding(#{n.inspect})") { "aaa".dup.force_encoding(n).encoding }
end
try("encode(x, X)") { "é".encode("x", "X") }
try("encode('', '')") { "a".encode("", "") }
try("encode(x, x) invalid") { "a".encode("x", "x", invalid: :replace) }
try("encode(wide, wide)") { "a".encode(wide, wide) }
try("encode(UTF-8, utf-8)") { "a".encode("UTF-8", "utf-8") }
try("rescue as ConverterNotFoundError") do
  "aaa".encode(wide)
rescue Encoding::ConverterNotFoundError => e
  [:converter, e.message.encoding]
end
try("String.new(encoding: nil)") { String.new("a", encoding: nil) }
try("String.new(encoding: 'UTF-16LE')") { String.new("ab", encoding: "UTF-16LE") }
try("String.new(encoding: false)") { String.new("a", encoding: false) }
try("String.new()") { String.new }
try("65.chr(nil)") { 65.chr(nil) }
try("65.chr(false)") { 65.chr(false) }
try("65.chr") { 65.chr }
try("233.chr") { 233.chr }
try("233.chr('UTF-8')") { 233.chr("UTF-8") }
try("prepend binary") { +"é".prepend("\xFF".b) }
try("prepend two") { +"é".prepend("a", "\xFF".b) }
try("prepend onto binary") { "\xFF".b.dup.prepend("é") }
try("prepend ascii") { +"é".prepend("a", "b") }
try("prepend none") { +"é".prepend }
