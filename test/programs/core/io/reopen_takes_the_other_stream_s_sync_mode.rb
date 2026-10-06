# IO#reopen(io) takes the other stream's mode, its sync flag too, so a
# write to a reopened STDOUT whose reader is gone fails at once.
io = STDOUT
save = io.dup
log = []
begin
  IO.popen("echo", "w", out: IO::NULL) do |f|
    log << [:popen_sync, f.sync]
    io.reopen(f)
    log << [:stdout_sync, io.sync]
    Process.wait(f.pid)
    begin
      io.print "foo\n"
      log << :printed
    rescue Errno::EPIPE => e
      log << [:epipe_at_print, e.message]
    end
  end
rescue => e
  log << [:outer, e.class, e.message]
ensure
  begin
    io.reopen(save)
  rescue => e
    log << [:reopen, e.class]
  end
end
STDERR.puts log.inspect
r, w = IO.pipe
w.sync = false
o = File.open(IO::NULL, "w")
o.sync = true
o.reopen(w)
f = File.open(IO::NULL, "w")
g = File.open(IO::NULL, "w")
g.reopen(STDERR)
STDERR.puts [o.sync, f.sync, g.sync].inspect
