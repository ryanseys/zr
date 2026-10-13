# Every Process::Status that a wait or a child run makes is frozen and so
# shareable: wait2, system, a fork's wait, a backtick, Status.wait and
# last_status. dup gives an unfrozen copy; an allocated one is not frozen.
s = Process.wait2(spawn("true"))[1]
p [s.frozen?, Ractor.shareable?(s), s.success?]
system("false")
p [$?.frozen?, Ractor.shareable?($?), $?.exitstatus]
pid = fork { exit 3 }
Process.wait(pid)
p [$?.frozen?, $?.exitstatus]
`true`
p $?.frozen?
p Process::Status.wait(spawn("true")).frozen?, Process.last_status.frozen?
p Process::Status.wait(-1).then { [_1.frozen?, _1.pid] }
begin
  $?.instance_variable_set(:@a, 1)
rescue => e
  p e.class
end
p $?.dup.frozen?, $?.clone.frozen?, Process::Status.allocate.frozen?
p Ractor.new { system("exit 2"); [$?.frozen?, $?.exitstatus] }.value
