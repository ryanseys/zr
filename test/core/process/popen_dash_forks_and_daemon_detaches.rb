# IO.popen("-") forks with pipes on the child's standard streams, and
# Process.daemon leaves the parent for a session of its own.
out = IO.popen("-") do |io|
  if io
    io.read
  else
    print "from the child #{Process.ppid == Process.pid ? :no : :yes}"
  end
end
p out, $?.success?
io = IO.popen("-", "r+")
if io
  io.puts "ping"
  io.close_write
  p io.read
  io.close
else
  $stdout.print "got #{$stdin.gets.chomp}"
  exit!(0)
end
r, w = IO.pipe
pid = fork do
  r.close
  Process.daemon(false, true)
  w.puts [Process.ppid != 0, Dir.pwd == "/"].inspect
  w.close
end
w.close
Process.wait(pid)
p r.read

__END__
"from the child yes"
true
"got ping"
"[true, true]\n"
