# ARGF.class.new reads the files it is given, and the program's ARGF
# reads ARGV itself, so a change to ARGV changes what it reads.
File.write("a.txt", "a1\na2\n")
File.write("b.txt", "b1\n")
own = ARGF.class.new("a.txt", "b.txt")
p own.argv, own.read, own.argv
one = ARGF.class.new("b.txt")
p [one.gets, one.filename, one.lineno]
p ARGF.argv.equal?(ARGV)
ARGV.replace(["a.txt"])
p ARGF.readlines
