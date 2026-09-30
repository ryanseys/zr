# A write turns each "\n" into what crlf, cr or lf names, puts and print
# included. The universal decorator changes nothing that is written, and
# neither does "wt".
path = "/tmp/zr_spec_newline_w.txt"
File.open(path, "w", crlf_newline: true) { |f| f.write("a\nb\r\nc") }
p File.binread(path)
File.open(path, "w", newline: :cr) { |f| f.write("a\nb") }
p File.binread(path)
File.open(path, "w", newline: :lf) { |f| f.write("a\r\nb\rc") }
p File.binread(path)
File.open(path, "w", newline: :universal) { |f| f.write("a\r\nb") }
p File.binread(path)
File.open(path, "wt") { |f| f.write("a\r\nb\n") }
p File.binread(path)
File.open(path, "w", crlf_newline: true) { |f| f.puts "x"; f.print "y\n"; f << "z\n" }
p File.binread(path)
File.delete(path)
