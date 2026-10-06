# Process.spawn: a [program, argv0] pair gives the child its argv[0],
# the env's PATH finds the program, an object with to_io is a redirect
# target, and two descriptors redirected to one name share one open.
require "tmpdir"

Dir.mktmpdir do |dir|
  tool = File.join(dir, "say-name")
  File.write(tool, "#!/bin/sh\necho \"${0##*/} $1\"\n")
  File.chmod(0o755, tool)

  pid = Process.spawn({ "PATH" => dir }, "say-name", "hi")
  Process.wait(pid)

  name = Object.new
  def name.to_str = "/bin/sh"
  pid = Process.spawn([name, "argv_zero"], "-c", "echo $0")
  Process.wait(pid)

  begin
    Process.spawn(["/bin/sh", "a\0b"], "-c", "true")
  rescue ArgumentError => e
    p e.message
  end

  out = File.join(dir, "both.txt")
  pid = Process.spawn("/bin/sh", "-c", "printf glark; printf bang >&2", [:out, :err] => out)
  Process.wait(pid)
  p File.read(out)

  holder = Object.new
  file = File.open(File.join(dir, "wrapped.txt"), "w")
  holder.define_singleton_method(:to_io) { file }
  pid = Process.spawn("/bin/sh", "-c", "echo wrapped", out: holder)
  Process.wait(pid)
  file.close
  p File.read(File.join(dir, "wrapped.txt"))
end
