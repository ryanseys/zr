# `alias $hit $&` is an alias of a global, so it reaches every file the
# program holds, not only the one that wrote it. What it answers is another
# matter: `$&` belongs to the frame that last matched, so a method of its
# own sees no match, and the frame that ran the match sees one.
require_relative "shouty"
"hello" =~ /l(l)o/
p Shouty.hit
p $hit
p $hit.frozen?
def here
  "abcd" =~ /b(c)/
  $hit
end
p here
p $hit
