# The collector closes the descriptor of a File that it frees, as CRuby's
# fptr_finalize does. A File that the program closed, or that gave up its
# descriptor, closes nothing: by then the number may belong to another
# file. At the end of the program the descriptors stay open for the
# program's own finalizers.
require "tmpdir"

def fds = Dir.children("/dev/fd").size
def open_some = 20.times { File.open(IO::NULL) }
before = fds
open_some
GC.start
p fds <= before

def closed_then_reused
  a = File.open(IO::NULL)
  a.close
  File.open(IO::NULL)
end
kept = closed_then_reused
GC.start
p kept.closed?, kept.stat.chardev?

def given_up
  f = File.open(IO::NULL)
  f.autoclose = false
  f.fileno
end
fd = given_up
GC.start
p IO.for_fd(fd, autoclose: false).closed?

p File.open(IO::NULL).instance_variables.include?(:@closer)

log = File.open(File.join(Dir.tmpdir, "zr-fd-#{Process.pid}"), "w")
ObjectSpace.define_finalizer(Object.new, proc { log.puts "written at exit"; log.flush; puts File.read(log.path); File.delete(log.path) })
