# A child process that ruby starts gets SIGPIPE back at its default
# action, also when the program ignores SIGPIPE, so the child ends by it.
# A signal that the program ignores otherwise stays ignored in the child.
trap(:PIPE, "IGNORE")
trap(:USR1, "IGNORE")
script = "kill -PIPE $$; echo survived"
p system("sh", "-c", script), $?.termsig == Signal.list["PIPE"]
p system("sh", "-c", script, umask: 0o22), $?.termsig == Signal.list["PIPE"]
pid = spawn("sh", "-c", script)
Process.wait(pid)
p $?.termsig == Signal.list["PIPE"]
p `sh -c 'kill -PIPE $$; echo survived'`, $?.termsig == Signal.list["PIPE"]
p system("sh", "-c", "kill -USR1 $$; echo usr1 ignored")
p system("sh", "-c", "kill -USR1 $$; echo usr1 ignored", umask: 0o22)
