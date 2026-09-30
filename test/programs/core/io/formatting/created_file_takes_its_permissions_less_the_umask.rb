# File.open and IO.sysopen create a file with open(2): the permissions
# given, less the umask, and O_EXCL for "x".
require "tmpdir"
Dir.mktmpdir do |d|
  File.umask(0o022)
  at = ->(name) { File.join(d, name) }
  mode = ->(name) { File.stat(at[name]).mode.to_s(8) }
  File.open(at["a"], "w", 0o640) { |io| io.write "x" }
  p mode["a"]
  File.open(at["a"], "w", 0o600) { |io| io.write "y" }
  p mode["a"], File.read(at["a"])
  p((File.open(at["a"], "wx") rescue $!.class))
  File.open(at["b"], "wx", 0o777) {}
  p mode["b"]
  File.open(at["c"], File::RDWR | File::CREAT, 0o604) { |io| io.write "rw"; io.rewind; p io.read }
  p mode["c"]
  p((File.open(at["c"], File::RDWR | File::CREAT | File::EXCL) rescue $!.class))
  File.open(at["c"], "a+") { |io| io << "z"; io.rewind; p io.read }
  File.open(at["c"], "r+") { |io| io << "Q" }
  p File.read(at["c"])
  p((File.open(at["nope"], "r") rescue $!.class), (File.open(at["nope"], "r+") rescue $!.class))
  fd = IO.sysopen(at["e"], "w", 0o700)
  p mode["e"], fd.class
  IO.for_fd(fd).close
  io = IO.new(IO.sysopen(at["e"], File::WRONLY | File::APPEND), "a")
  io.write("tail")
  io.close
  p File.read(at["e"])
  File.umask(0o077)
  File.write(at["g"], "g")
  p mode["g"]
end

