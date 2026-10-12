# String#=~ and Symbol#=~ with a String, as rb_str_match raises it:
# "type mismatch: String given". Found by zr-dev fuzz.
def try(label)
  puts "#{label}: #{yield.inspect}"
rescue StandardError => e
  puts "#{label}: #{e.class}: #{e.message}"
end

try("str =~ str") { "b" =~ "" }
try("sym =~ str") { :b =~ "" }
try("public_send(:=~, str)") { %i[b].max.public_send(:=~, "") }
try("subclass") { Class.new(String).new("x") =~ "x" }
try("str =~ regexp") { "abc" =~ /c/ }
try("sym =~ regexp") { :abc =~ /b/ }
try("str =~ nil") { "abc" =~ nil }
try("str =~ Integer") { "abc" =~ 1 }
try("own =~") { o = Object.new; def o.=~(s) = "own: #{s}"; "abc" =~ o }
try("sym.match(str)") { :b.match("b") }
try("str.match(str)") { "ab".match("b") }
