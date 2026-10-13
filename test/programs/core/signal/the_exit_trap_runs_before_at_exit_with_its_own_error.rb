# The EXIT trap runs as the program ends, before the at_exit handlers.
# An error in it is held while the handlers run, with $! nil, and is
# then reported and sets the status. A signal that comes while the trap
# runs waits: it is handled as each at_exit handler starts, so the
# signal of a default handler stops the first one, and with no handler
# it is lost.
def run(&block)
  r, w = IO.pipe
  pid = fork do
    r.close
    $stdout.reopen(w)
    $stderr.reopen(w)
    $stdout.sync = true
    block.call
  end
  w.close
  out = r.read
  Process.wait(pid)
  [out.lines.map { it.sub(/\A\S+:\d+:in /, "...:in ") }, $?.exitstatus, $?.termsig]
end

p run { trap(:EXIT) { puts "trap" }; at_exit { puts "at_exit" }; puts "main" }
p run { trap(:EXIT) { raise "in trap" }; at_exit { p [:at_exit, $!] } }
p run { trap(:EXIT) { p [:trap, $!] }; at_exit { p [:at_exit, $!] }; raise "in main" }
p run { trap(:EXIT) { exit 7 }; at_exit { p [:at_exit, $!] } }
p run { trap(:EXIT) { Process.kill(:TERM, $$); puts "after kill" }; at_exit { puts "at_exit" } }
p run { trap(:EXIT, "EXIT"); at_exit { puts "at_exit" } }
p run { trap(:EXIT) { puts "once" }; trap(:EXIT, "DEFAULT"); at_exit { puts "at_exit" } }
p run { trap(:EXIT) { Process.kill(:TERM, $$); puts "after kill" } }
p run { trap(:EXIT) { Process.kill(:TERM, $$) }; at_exit { puts "first" }; at_exit { puts "second" } }
p run { trap(:EXIT) { Process.kill(:USR1, $$) }; trap(:USR1) { puts "usr1" }; at_exit { puts "at_exit" } }
