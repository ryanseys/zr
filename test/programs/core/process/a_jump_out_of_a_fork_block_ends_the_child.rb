# In the child, a fork block runs under rb_protect: a `break` or `return`
# that leaves it ends the child with exit 1, after the exit handlers,
# with the message at the call of `fork`. A SignalException that an exit
# handler raises ends the process by its signal.
def child
  r, w = IO.pipe
  pid = yield w
  w.close
  text = r.read.gsub(__FILE__, "FILE")
  r.close
  _, status = Process.wait2(pid)
  [text, status.exitstatus, status.termsig]
end

p(child do |w|
  fork do
    $stderr.reopen(w)
    at_exit { $stderr.puts $!.class }
    break
  end
end)

def returning(w)
  fork do
    $stderr.reopen(w)
    return
  end
end

p(child { |w| returning(w) })

p(child do |w|
  Process.fork do
    $stderr.reopen(w)
    break
  end
end)

p(child do |w|
  fork do
    $stderr.reopen(w)
    at_exit { $stderr.puts "after" }
    at_exit { raise SignalException, "TERM" }
  end
end)

p(child do |w|
  fork do
    $stderr.reopen(w)
    at_exit { raise SignalException, "TERM" }
    exit 5
  end
end)

p(child do |w|
  fork do
    $stderr.reopen(w)
    at_exit { exit 3 }
    raise SignalException, "TERM"
  end
end)

p(child do |w|
  fork do
    $stderr.reopen(w)
    at_exit { raise "y" }
    exit 5
  end
end)
