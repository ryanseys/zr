#@ args: core/io/argf_walk/a.txt core/io/argf_walk/b.txt
# ARGF is one stream over the files ARGV names: each opens as the walk
# reaches it, the line numbers run on across the whole set, and ARGV
# empties as the walk goes.
def e; p(yield); rescue => x; puts "#{x.class}: #{x.message}"; end
e { ARGF.class.name }
e { ARGF.class.ancestors.first(3) }
e { ARGF.filename }
e { ARGF.argv }
e { ARGF.lineno }
e { ARGF.eof? }
rows = []
ARGF.each_line { |l| rows << [ARGF.filename, ARGF.lineno, l] }
p rows
e { ARGF.lineno }
e { ARGF.eof? }
e { ARGF.gets }
e { ARGF.argv }
e { ARGF.to_s }
e { ARGF.inspect }
__END__
"ARGF.class"
[ARGF.class, Enumerable, Object]
"core/io/argf_walk/a.txt"
["core/io/argf_walk/b.txt"]
0
false
[["core/io/argf_walk/a.txt", 1, "one\n"], ["core/io/argf_walk/a.txt", 2, "two\n"], ["core/io/argf_walk/b.txt", 3, "three\n"]]
3
IOError: closed stream
nil
[]
"ARGF"
"ARGF"
