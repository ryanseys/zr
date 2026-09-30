# Empty-pattern split drops the leading zero-width field; \k<name> expands
# in a replacement (unknown name -> IndexError); rindex/rpartition find the
# rightmost anchored match start; match? honors a start position.

p "abc".split(//)
p "abc".split(//, -1)
puts "foobar".gsub(/(?<x>o+)/, "[\\k<x>]")
r = (begin; "x".gsub(/(?<a>x)/, "\\k<y>"); rescue => e; e.class; end)
p r
p "hello123world".rindex(/\d+/)
p "hello123world".rpartition(/\d+/)
p(/hello/.match?("hello world", 6))
p(/world/.match?("hello world", 6))
