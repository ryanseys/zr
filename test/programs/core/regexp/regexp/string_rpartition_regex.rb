# String#rpartition with a regex: the regex form must locate the *last*
# match by start position: \d+ in "hello123world" matches at 5/6/7, so
# the rightmost is the single "3" (not "123").
puts "hello123world".rpartition(/\d+/).inspect
puts "foo1bar2baz".rpartition(/\d/).inspect
puts "no digits here".rpartition(/\d+/).inspect
puts "a.b.c".rpartition(".").inspect
puts "abc".rpartition("x").inspect
