# spawn resolves a chain of [:child, fd] redirects, and refuses a cycle,
# a child fd no option names, a fd named twice, a duplex stream and a
# resource limit in upper case, as ruby does.
require "tmpdir"
def t
  r = yield
  p r
rescue => e
  p [e.class, e.message]
end
t { system("true", :rlimit_NOFILE => 0) }
t { system("true", :rlimit_nofile => [1, 2, 3]) }
t { Process.wait spawn("true", STDOUT => [:child, STDOUT]) }
t { Process.wait spawn("true", 3 => [:child, 4], 4 => [:child, 3]) }
t { Process.wait spawn("true", STDOUT => [:child, 3]) }
t { IO.popen(["echo", "qux", STDOUT => STDOUT]) {} }
t { IO.popen(["cat", STDIN => STDIN], "r+") {} }
t { IO.popen(["cat", STDIN => STDIN]) { |io| io.read } }
IO.popen("cat", "r+") do |d|
  t { system("true", d => STDOUT) }
  t { system("true", STDOUT => d) }
end
t { IO.popen([{ "A" => "B" }, "env", unsetenv_others: true], &:read) }
Dir.chdir(Dir.mktmpdir) do
  Process.wait spawn("ruby", "-e", "STDERR.print 'err'; STDOUT.print 'out'",
                     STDOUT => "out", STDERR => [:child, 3], 3 => [:child, 4], 4 => [:child, STDOUT])
  p File.read("out")
end
