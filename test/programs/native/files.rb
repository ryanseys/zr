# Files come from libSystem.
dir = "#{ENV["TMPDIR"] || "/tmp"}/ze0-files-test"
if Dir.exist?(dir)
  Dir.each_child(dir) { |name| File.delete("#{dir}/#{name}") }
  Dir.rmdir(dir)
end
p Dir.mkdir(dir), Dir.exist?(dir), Dir.empty?(dir), Dir.children(dir), Dir.each_child(dir).to_a, Dir.entries(dir).sort
path = "#{dir}/a.txt"
p File.write(path, "one\ntwo\nthree"), File.read(path), File.size(path), File.exist?(path), File.file?(path), File.zero?(path), File.size?(path), File.empty?(path), File.readable?(path), File.writable?(path), File.executable?(path)
p File.readlines(path), File.readlines(path, chomp: true), File.foreach(path).to_a, File.foreach(path, chomp: true).map(&:upcase), File.read(path, 3), File.read(path, 3, 4), File.read(path, 100, 12), File.read(path, 100, 14)
File.open(path, "a") { |f| f.puts "four"; f.print "fi", "ve"; f << "\n" << 6; f.write("\n", "seven", "\n"); f.printf("%03d\n", 8) }
p File.read(path)
File.open(path, "w") { |f| p f.class, f.path, f.fileno > 2, f.closed?, f.sync, f.tty?, f.inspect.end_with?("a.txt>"), f.write("x"), f.write("ab", "cd"), f.puts, f.puts(nil), f.puts([]), f.puts([1, [2]]), f.print(1, 2), f.puts("z\n"), (f.read rescue $!.class), f.pos }
p File.read(path), File.open(path).read, File.open(path) { |f| f.read(2) }, File.open(path, "r") { |f| [f.gets, f.gets, f.gets, f.gets, f.gets, f.gets, f.gets, f.gets, f.eof?, f.lineno] }
File.open(path, "w") { |f| f.write("a\nbb\n\nccc") }
f = File.open(path)
p f.gets, f.lineno, f.gets(""), f.gets(nil), f.gets, f.eof?, f.close, f.closed?, (f.gets rescue $!.message), (f.read rescue $!.class), f.inspect.end_with?("(closed)>"), (f.close rescue $!.class)
p File.open(path) { |g| g.each_line.to_a }, File.open(path) { |g| g.each_line(chomp: true).to_a }, File.open(path) { |g| g.readlines }, File.open(path) { |g| g.readlines(chomp: true) }, File.open(path) { |g| g.each_line("") .to_a }, File.open(path) { |g| g.readline }, File.open(path) { |g| g.read; (g.readline rescue $!.message) }, File.open(path) { |g| [g.getc, g.getc, g.readchar, g.read(1), g.read(0), g.read(100), g.read(1), g.read, g.getc] }, File.open(path) { |g| g.each_char.first(3) }, File.open(path) { |g| g.each_byte.first(3) }
p File.open(path) { |g| [g.read(1), g.pos, g.seek(3), g.pos, g.read(2), g.rewind, g.pos, g.gets, g.seek(-3, IO::SEEK_END), g.read, g.seek(1, IO::SEEK_CUR), g.eof?] }, File.open(path) { |g| g.each_with_index.to_a }, File.open(path, "r+") { |g| g.write("Z"); g.rewind; g.read }, File.open(path, "w+") { |g| g.write("new"); g.rewind; g.read }, File.read(path), File.open(path, "a+") { |g| g.write("!"); g.rewind; g.read }
begin
  File.read("#{dir}/nope")
rescue Errno::ENOENT => e
  p e.class, e.message, e.errno, e.class::Errno, e.class.superclass, e.is_a?(SystemCallError), e.is_a?(StandardError)
end
begin
  File.open("#{dir}/nope") { }
rescue SystemCallError => e
  p e.class, e.message
end
begin
  File.open(dir, "w")
rescue Errno::EISDIR => e
  p e.message
end
begin
  File.delete("#{dir}/nope")
rescue Errno::ENOENT => e
  p e.message
end
begin
  File.open(path, "q")
rescue ArgumentError => e
  p e.message
end
begin
  File.open("#{dir}/nope/deep", "w")
rescue Errno::ENOENT => e
  p e.message
end
p Errno::ENOENT.new.message, Errno::ENOENT.new("x").message, SystemCallError.new("y", 2).class, SystemCallError.new("y", 2).message, SystemCallError.new(2).message, SystemCallError.new(nil, 99999).class, SystemCallError.new(nil, 99999).message, Errno::EACCES::Errno, Errno::EEXIST.new.message, Errno::EBADF.new.message, Errno::EINVAL.new.message, Errno::ENOTDIR.new.message, Errno::EPIPE.new.message, Errno::EISDIR.new.message, Errno::ENOTEMPTY.new.message, Errno::EAGAIN.new.message
other = "#{dir}/b.txt"
p File.rename(path, other), File.exist?(path), File.exist?(other), File.delete(other), File.exist?(other), File.open("#{dir}/c.txt", "w") { |g| g.write("c") }, File.write("#{dir}/d.txt", "d", mode: "a"), File.write("#{dir}/d.txt", "d", mode: "a"), File.read("#{dir}/d.txt"), File.unlink("#{dir}/c.txt", "#{dir}/d.txt"), Dir.exist?(dir), Dir.empty?(dir), Dir.rmdir(dir), Dir.exist?(dir)
p $stdout.class, $stdout.fileno, $stderr.fileno, $stdin.fileno, STDOUT.equal?($stdout), STDERR.equal?($stderr), STDIN.equal?($stdin), $stdout.inspect, $stderr.inspect, $stdin.inspect, $stdout.sync, $stderr.sync, $stdout.tty?, $stdout.closed?, $stdout.flush.equal?($stdout), $stdout.write("w\n"), $stdout.print("p\n"), $stdout.puts("q"), ($stdout << "r" << "\n").equal?($stdout), $stdout.printf("%s\n", "s"), $stdout.external_encoding, $stdout.binmode?, $stdout.path, ($stdout.read rescue $!.class), STDOUT.sync = true, $stdout.sync, $>.equal?($stdout)
$stderr.puts "to stderr"
STDERR.print "err2\n"
$stderr.write("err3\n")
warn "warned"
class Sink
  attr_reader :got
  def initialize = @got = +""
  def write(*args) = args.each { |a| @got << a.to_s }
end
sink = Sink.new
old = $stdout
$stdout = sink
puts "captured", 1, [2, [3]], nil
print "a", "b"
p :sym
$stdout = old
p sink.got
$stdout = STDOUT
p Kernel.respond_to?(:puts), STDOUT.respond_to?(:puts), IO.instance_method(:puts).owner, File.superclass, File.ancestors.include?(Enumerable), IO::SEEK_SET, IO::SEEK_CUR, IO::SEEK_END, File::RDONLY, File::WRONLY, File::RDWR, File::APPEND, File::CREAT, File::TRUNC, File::EXCL
p File.open("/dev/null").read, File.open("/dev/null", "w") { |g| g.write("gone") }, File.read("/dev/null"), File.exist?("/dev/null"), File.file?("/dev/null"), File.directory?("/tmp"), File.size("/dev/null")
