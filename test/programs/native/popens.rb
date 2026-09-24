# Pipes to a child process, redirections and the status a stream carries.
# no stress
require "tmpdir"

p IO.popen(["echo", "hi"], &:read)
p IO.popen("echo shell here", &:read)
io = IO.popen(["echo", "kept"])
p io.pid.is_a?(Integer), io.read
io.close
p $?.success?, $?.exitstatus

p IO.popen(["sh", "-c", "echo out; echo err 1>&2"], err: %i[child out], &:read).split("\n").sort
p IO.popen(["sh", "-c", "echo only out; echo err 1>&2"], &:read)

IO.popen(["cat"], "w") { |w| w.write("swallowed\n") }
p $?.exitstatus

p IO.popen(["sh", "-c", "exit 3"], &:read)
p $?.exitstatus

p `echo backtick`
p `sh -c 'exit 7'`, $?.exitstatus

Dir.mktmpdir do |dir|
  out = File.join(dir, "out.txt")
  system("echo", "redirected", out: out)
  p File.read(out)
  system("sh", "-c", "echo boom 1>&2", err: out)
  p File.read(out)
  p system("pwd", chdir: dir, out: out)
  p File.read(out).chomp == File.realpath(dir)
  p system({ "ZR_SPAWN" => "yes" }, "sh", "-c", "echo $ZR_SPAWN", out: out)
  p File.read(out)
  p system({ "ZR_SPAWN" => nil }, "sh", "-c", "echo [$ZR_SPAWN]", out: out)
  p File.read(out)
  system("sh", "-c", "echo quiet", out: File::NULL)
  p $?.success?
end

p system("this-command-does-not-exist-zr")
begin
  IO.popen(["this-command-does-not-exist-zr"], &:read)
rescue SystemCallError => e
  p e.class
end
begin
  IO.popen(["cat"], "x")
rescue ArgumentError => e
  p e.message
end
