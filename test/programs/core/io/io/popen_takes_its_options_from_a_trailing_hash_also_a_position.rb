# A Hash after the command is the options, also as a positional
# argument, and a Hash before it is the environment.
opts = [{ err: [:child, :out] }]
p IO.popen("echo out; echo err 1>&2", *opts, &:read)
p IO.popen("echo x", "r", { err: File::NULL }, &:read)
p IO.popen({ "V" => "1" }, "echo $V", &:read)
