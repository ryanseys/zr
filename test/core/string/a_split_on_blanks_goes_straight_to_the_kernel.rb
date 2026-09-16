# A split with no pattern, or on " ", with no limit takes the kernel's
# word scan; it agrees with the limit forms, `$;`, a block, tabs and
# newlines, and IO#each_line counts `$.` without touching `$_`.
p "  a  b\tc\n".split, "  a  b\tc\n".split(" "), "  a  b\tc\n".split(" ", 2), "  a  b\tc\n".split(" ", -1)
p "".split, " ".split, "a".split, " a ".split(" ", 2), "a b ".split(" ", -1)
p "x y z".split { |w| print w }, " a b".split
puts
class Sep < String; end
p "a b".split(Sep.new(" ")), "a\0b c".split, "a,b c".split(",")
$; = ","
p "a,b c".split, "a,b c".split(" ")
$; = nil
p "a,b c".split
p "ä ö".split.map(&:encoding).uniq, ("\xff a".dup.force_encoding("UTF-8").split rescue $!.class)
require "stringio"
io = StringIO.new("one\ntwo\nthree\n")
$_ = "kept"
io.each_line { |l| print l.chomp, " " }
puts
p $., $_
io.rewind
p io.gets, $_, $.
p StringIO.new("a\nb").each_line(chomp: true).to_a, StringIO.new("a\nb").each_line("").to_a

__END__
["a", "b", "c"]
["a", "b", "c"]
["a", "b\tc\n"]
["a", "b", "c", ""]
[]
[]
["a"]
["a", ""]
["a", "b", ""]
xyz"x y z"
[" a", "b"]

["a", "b"]
["a\u0000b", "c"]
["a", "b c"]
["a", "b c"]
["a,b", "c"]
["a,b", "c"]
[#<Encoding:UTF-8>]
ArgumentError
one two three 
0
"kept"
"one\n"
"one\n"
0
["a", "b"]
["a\nb"]
