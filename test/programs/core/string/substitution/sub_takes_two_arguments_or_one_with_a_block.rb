# String#sub and #sub! check their arity as rb_str_sub_bang does: two
# arguments, or one with a block. With no block, the message says that
# 2 are expected; with a block, 1..2. gsub returns an enumerator for one
# argument and no block, so it always says 1..2. Found by zr-dev fuzz.
def try(label)
  puts "#{label}: #{yield.inspect}"
rescue StandardError => e
  puts "#{label}: #{e.class}: #{e.message}"
end

try("sub()") { "hello".sub }
try("sub(1)") { "hello".sub("l") }
try("sub(3)") { "hello".sub("l", "L", "x") }
try("sub(4)") { "hello".sub("l", "L", "x", "y") }
try("sub() {}") { "hello".sub { "L" } }
try("sub(3) {}") { "hello".sub("l", "L", "x") { "L" } }
try("sub!()") { +"hello".sub! }
try("sub!(1)") { (+"hello").sub!("l") }
try("sub!(3)") { (+"hello").sub!("l", "L", "x") }
try("sub!() {}") { (+"hello").sub! { "L" } }
try("sub!(3) {}") { (+"hello").sub!("l", "L", "x") { "L" } }
try("gsub()") { "hello".gsub }
try("gsub(3)") { "hello".gsub("l", "L", "x") }
try("gsub!()") { (+"hello").gsub! }

# The arity error comes before the frozen check, as in ruby.
try("frozen sub!()") { "hello".freeze.sub! }
try("frozen sub!(1)") { "hello".freeze.sub!("l") }
try("frozen sub!(2)") { "hello".freeze.sub!("l", "L") }

# public_send and send take the same path, with the same message.
try("public_send(:sub)") { "hello".public_send(:sub) }
try("send(:sub!, 'l')") { (+"hello").send(:sub!, "l") }
try("method(:sub).call") { "hello".method(:sub).call("l", "L", "x") }

# The working forms.
try("sub(2)") { "hello".sub("l", "L") }
try("sub(regexp, hash)") { "hello".sub(/[el]/, "e" => "3", "l" => "1") }
try("sub(1) {}") { "hello".sub(/l+/) { |m| m.upcase } }
try("sub(2) {} uses the replacement") { "hello".sub("l", "L") { "block" } }
try("sub with $~") { "hello".sub(/(l)(l)/) { "#{$2}#{$1}!" } }
try("no match") { "hello".sub("z", "Z") }
try("sub!(2)") { (+"hello").sub!("l", "L") }
try("sub! no match") { (+"hello").sub!("z", "Z") }
try("sub!(1) {}") { (+"hello").sub!(/o\z/) { "0" } }
try("nil replacement") { "hello".sub("l", nil) }

# The method itself, as reflection sees it.
p "".method(:sub).arity, "".method(:sub!).arity
p "".method(:sub).parameters, "".method(:sub!).parameters

# The backtrace names String#sub, not a helper.
begin
  "hello".sub
rescue ArgumentError => e
  p e.backtrace_locations.first.label
end
begin
  (+"hello").sub!("l")
rescue ArgumentError => e
  p e.backtrace_locations.first.label
end

# A subclass's sub goes through the same check.
class Shout < String; end
try("subclass sub()") { Shout.new("hey").sub }
try("subclass sub(2)") { Shout.new("hey").sub("e", "E").class }
