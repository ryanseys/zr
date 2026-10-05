# CRuby closes the descriptor of a File that the collector frees
# (fptr_finalize), and a call that runs out of descriptors collects and
# tries again (rb_gc_for_fd). zr closes a File only when the program does.
def open_some = 20.times { File.open(IO::NULL) }
before = Dir.children("/dev/fd").size
open_some
GC.start
p Dir.children("/dev/fd").size <= before
