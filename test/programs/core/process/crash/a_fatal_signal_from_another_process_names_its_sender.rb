# A fatal signal that another process sends adds `(sent by pid N)` to the
# report's first line. One that the process sends to itself adds nothing.
def report
  r, w = IO.pipe
  ready_r, ready_w = IO.pipe
  pid = fork do
    r.close
    ready_r.close
    $stderr.reopen(w)
    yield ready_w
  end
  w.close
  ready_w.close
  ready_r.gets
  [pid, r]
end

pid, r = report { |ready| ready.puts "ready"; sleep }
Process.kill(:ABRT, pid)
text = r.read
Process.wait(pid)
first = text.lines.first
p first.end_with?(" (sent by pid #{Process.pid})\n"), first.include?("[BUG] Aborted at 0x")
p $?.termsig == Signal.list["ABRT"]

pid, r = report { |ready| ready.puts "ready"; Process.kill(:SEGV, $$) }
text = r.read
Process.wait(pid)
p text.lines.first.include?("sent by")
