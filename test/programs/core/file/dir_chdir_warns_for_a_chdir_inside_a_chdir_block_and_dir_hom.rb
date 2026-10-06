# Dir.chdir with no argument goes home, and nil is a TypeError. A chdir
# with no block inside a chdir block warns, with where the block began;
# one inside another thread's block is an error.
require "tmpdir"
p((Dir.chdir(nil) rescue $!))
Dir.chdir(Dir.tmpdir) { Dir.chdir(Dir.tmpdir) { :nested } }
Dir.chdir(Dir.tmpdir) do
  Dir.chdir("/")
end
Dir.chdir(Dir.tmpdir) { p((Thread.new { Thread.current.report_on_exception = false; Dir.chdir("/") }.join rescue $!)) }
p Dir.home("") == Dir.home, (Dir.home("nosuchuserzz") rescue $!), (Dir.home(1) rescue $!)
