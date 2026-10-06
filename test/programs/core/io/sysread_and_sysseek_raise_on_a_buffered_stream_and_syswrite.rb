# sysread and sysseek go past the buffer, so a buffer with bytes in it is
# an error; syswrite warns about one, with the program's line.
path = "/tmp/zr_spec_sysread.txt"
File.write(path, "ab\ncd\n")
File.open(path) { |f| f.gets; p((f.sysread(1) rescue $!)) }
File.open(path) { |f| f.gets; p((f.sysseek(0) rescue $!)) }
File.open(path) { |f| p f.sysread(2) + f.sysread(1) }
File.open(path) { |f| p [f.sysseek(1), f.sysread(1)] }
File.open(path, "r+") { |f| f.ungetc("z"); p((f.sysseek(0) rescue $!)) }
File.open(path, "w") { |f| f.write("x"); f.syswrite("y") }
p File.read(path)
File.delete(path)
