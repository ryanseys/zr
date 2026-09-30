# ARGF reads on across its files as io.c's does: a length reads into the
# next file, readpartial ends a file with "", and close moves on.
File.write("/tmp/zr_af1", "abc\ndef\n")
File.write("/tmp/zr_af2", "ghé\nij")
def a = ARGF.class.new("/tmp/zr_af1", "/tmp/zr_af2")
f = a
p [f.read(2), f.read(2), f.read(5), f.read(100), f.read(1)]
f = a
p [f.read(2).encoding, f.read.encoding]
f = a
p [f.read(0), f.readpartial(3), f.readpartial(100), f.readpartial(100), f.readpartial(100), (f.readpartial(1) rescue $!)]
f = a
p [f.gets, f.close, f.gets, f.filename, f.closed?, f.lineno]
f = a
p [f.skip.filename, f.gets, f.skip.gets]
f = a
f.gets
f.rewind
p [f.gets, f.lineno]
f = a
f.readlines
p [f.gets, f.read, f.filename, (f.pos rescue $!)]
File.delete("/tmp/zr_af1", "/tmp/zr_af2")
