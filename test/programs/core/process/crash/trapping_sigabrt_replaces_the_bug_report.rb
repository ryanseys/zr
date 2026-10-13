# ruby handles SIGABRT with its bug report, so the first trap of it
# returns nil, as for any handler that is not ruby's own trap handler.
# A trap replaces the report; "DEFAULT" and "SYSTEM_DEFAULT" give the
# system's action, which ends the process with no report. SIGSEGV, SIGBUS
# and SIGILL are reserved, so a trap of them raises.
p trap(:ABRT) { puts "trapped" }
Process.kill(:ABRT, $$)
sleep 0.1
p trap(:ABRT, "DEFAULT").class
p trap(:ABRT, "SYSTEM_DEFAULT")
%i[SEGV BUS ILL].each do |signal|
  trap(signal) {}
rescue ArgumentError => e
  p e.message
end

r, w = IO.pipe
pid = fork do
  r.close
  $stderr.reopen(w)
  trap(:ABRT, "DEFAULT")
  Process.kill(:ABRT, $$)
end
w.close
p r.read
Process.wait(pid)
p $?.termsig == Signal.list["ABRT"]
