# A String literal in a file that sets no frozen_string_literal is
# chilled: not frozen, but +@ copies it, and its first change warns when
# deprecation warnings are on. Symbol#to_s chills its String too.

s = "abc"
t = +s
p t.equal?(s), s.frozen?
t << "x"
p s
u = +"lit"
p((+u).equal?(u))
Warning[:deprecated] = true
%w[upcase! downcase! capitalize! swapcase! reverse! strip! squeeze! succ! chop! chomp! lstrip! clear].each do |m|
  x = "Abc "
  x.public_send(m)
end
[
  -> { a = "a"; a.concat("b") },
  -> { a = "a"; a.replace("b") },
  -> { a = "a"; a[0] = "b" },
  -> { a = "a"; a.insert(0, "b") },
  -> { a = "a"; a.prepend("b") },
  -> { a = "a"; a.force_encoding("BINARY") },
  -> { a = "a"; a.setbyte(0, 66) },
  -> { a = "a"; a.sub!("a", "b") },
  -> { a = "a"; a.gsub!("a", "b") },
  -> { a = "a"; a.tr!("a", "b") },
  -> { a = "a"; a.slice!(0) },
  -> { a = "a"; a.encode!("UTF-16LE") },
  -> { a = "a"; a.instance_variable_set(:@x, 1) },
  -> { a = "a"; a.freeze; p a.frozen? },
  -> { a = "a"; b = a.clone(freeze: false); b << "x" },
  -> { a = "a"; b = a.dup; b << "x" },
  -> { a = "a"; p a.frozen?; b = -a; p b.frozen? },
  -> { a = :sym.to_s; a << "!" },
  -> { a = :sym.name; p a.frozen? },
  -> { a = "a" "b"; a << "c" },
  -> { a = 'q'; a << "c" },
  -> { a = <<~X; a << "y" },
    text
  X
]
.each_with_index { |f, i| $stderr.puts i; f.call }
$VERBOSE = nil
x = "v"
x << "w"

