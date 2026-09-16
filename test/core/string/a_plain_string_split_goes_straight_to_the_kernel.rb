# A split by a String pattern other than " " or "" with no limit takes
# the kernel's path first; the answers agree with every other form.
p "a,b,,c,,".split(",")
p "a,b,,c,,".split(",", -1)
p "a,b,,c,,".split(",", 2)
p "a,b,,c,,".split(",", 0)
p ",,".split(",")
p "".split(",")
p "abc".split(",")
p "a--b--c".split("--")
p " a  b ".split(" ")
p "abc".split("")
p "a,b".split(",", 1)
p "a,b,c".split(",") { |x| print x.upcase }
puts
class Sep < String; end
p "a;b;c".split(Sep.new(";"))
p "a b".split(Sep.new(" "))
p "x,y".split(",", 0.0)
p "x,y".split(",", nil.to_a.size)
p "a,b,c".split(",", 2 ** 70) rescue p $!.class
p "ä,ö".split(",").map(&:encoding).uniq
p "a,b".split(",".encode("UTF-16LE")) rescue p $!.class
p "\xff,b".dup.force_encoding("UTF-8").split(",") rescue p $!.class
p "a,b".split(",".b)
p "a,b".split(:",") rescue p $!.class

__END__
["a", "b", "", "c"]
["a", "b", "", "c", "", ""]
["a", "b,,c,,"]
["a", "b", "", "c"]
[]
[]
["abc"]
["a", "b", "c"]
["a", "b"]
["a", "b", "c"]
["a,b"]
ABC"a,b,c"

["a", "b", "c"]
["a", "b"]
["x", "y"]
["x", "y"]
RangeError
[#<Encoding:UTF-8>]
Encoding::CompatibilityError
ArgumentError
["a", "b"]
TypeError
