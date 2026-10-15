# system(exception: true) raises RuntimeError for a command that ran and
# failed. The message names how it ended and the command: a shell script
# whole, else only the program's name.
def failed(*args)
  system(*args, exception: true, err: File::NULL)
rescue RuntimeError => e
  e.message
end

p failed("sh", "-c", "exit 4")
p failed(["sh", "my-shell"], "-c", "exit 3")
p failed("exit 5")
p failed("false x y")
p failed("  false")
p failed("/usr/bin/false a b")
p failed({ "A" => "1" }, "false", "q")
p failed("false; true; false")
p failed("sh", "-c", "kill -9 $$")
p failed("kill -9 $$")
p failed("A=1 false")
p failed("true"), failed("true", "x")
