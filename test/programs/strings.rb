# frozen_string_literal: true
puts "abc".upcase, "ABC".downcase, "abc".length, "abc".reverse, "a" + "b", "ab" * 3
s = "hello"
puts s.capitalize, s.include?("ell"), s.index("l"), s.index("zz").inspect
p "x".succ, "az".succ, "zz".succ, "a9".succ, "Zz".succ, "1.9".succ, "-".succ, "".succ
name = "world"
count = 3
def wrap(x) = "<#{x}>"
puts "hello, #{name}! #{count} #{count * 2} #{1 + 2}"
puts "#{wrap(1)} #{wrap("two")} #{wrap(nil)} #{[1, :a]}"
t = "x"
t += "y"
p t, t == "xy", t != "xy", t.empty?, "".empty?, "ab".to_sym, s.frozen?, t.frozen?, s.dup.frozen?
u = "a".dup
u << "b" << "c"
p u
s << "!"
