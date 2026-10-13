# ruby catches SIGVTALRM and does nothing with it, so the signal does
# not end the process, and the signal stays reserved for a trap.
Process.kill(:VTALRM, $$)
sleep 0.1
puts "alive"
begin
  trap(:VTALRM) {}
rescue ArgumentError => e
  p e.message
end
pid = fork { sleep 0.3; puts "child alive" }
Process.kill(:VTALRM, pid)
Process.wait(pid)
p $?.success?
