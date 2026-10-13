# exec replaces the process without writing out the buffers of the
# standard streams: ruby's exec skips the flush that fork, spawn and
# system make first. Bytes still in a buffer are lost; sync and flush
# keep them.
def child(&block)
  pid = fork(&block)
  Process.wait(pid)
  puts "exit #{$?.exitstatus}"
end

child { print "lost "; exec "echo", "exec 1" }
child { puts "lost line"; exec "echo exec 2" }
child { $stdout.sync = true; print "kept "; exec "echo", "exec 3" }
child { print "flushed "; $stdout.flush; exec "echo", "exec 4" }
child { $stdout.write("lost "); exec ["echo", "echo"], "exec 5" }
child { $stderr = $stdout; $stderr.print "lost "; exec "echo exec 6" }
child { STDOUT.print "lost "; Process.exec("echo", "exec 7") }

# A failed exec keeps the buffer, and the process goes on.
child do
  print "kept "
  begin
    exec "zr-test-no-such-command"
  rescue SystemCallError => e
    puts e.class
  end
end

# fork, spawn and system write the buffers out first.
print "before system "
system "echo system"
print "before spawn "
Process.wait(spawn("echo spawn"))
print "before fork "
child { puts "in fork" }
