
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
