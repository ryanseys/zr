# In a child that a thread forked, that thread is the main thread, so its
# exit or its end ends the child, with the at_exit handlers.
at_exit { puts "at_exit in #{Process.pid == $parent ? "parent" : "child"}" }
$parent = Process.pid
th = Thread.new do
  pid = fork
  unless pid
    STDOUT.puts "child"
    exit 3
  end
  Process.wait2(pid)[1].exitstatus
end
p th.value
th = Thread.new do
  io = IO.popen("-")
  next [io.read, Process.wait2(io.pid)[1].success?] if io

  puts "child of popen"
end
p th.value
