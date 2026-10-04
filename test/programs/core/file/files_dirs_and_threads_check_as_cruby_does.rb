# Thread, File, Dir, ENV and NameError: conversions, checks and
# messages as CRuby gives them (each line names its case by number).
def show(label)
  r = yield
  puts "#{label}: #{r.inspect}"
rescue Exception => e
  puts "#{label}: #{e.class}: #{e.message}"
end
require "tmpdir"
dir = Dir.mktmpdir
path = File.join(dir, "f.txt")
File.write(path, "hello")
show(1) { Thread.each_caller_location }
show(2) { Thread.each_caller_location(foo: 1) { } }
t = Thread.new { }
t.join
t.freeze
show(3) { t[:a] = 1 }
show(4) { t.thread_variable_set(:a, 1) }
show(5) { t.thread_variable_get(:a) }
show(6) { t.thread_variable?(:a) }
show(7) { Thread.current.thread_variable_get(123) }
show(8) { Thread.current.thread_variable?(123) }
s = Object.new; def s.to_sym = :x
show(11) { Thread.current.name = "a\0b" }
m = Object.new; def m.to_int = 0o644
show(12) { File.chmod(m, path) }
show(13) { File.chmod(2**64, path) }
show(14) { File.open(path) { |f| f.chmod(m) } }
show(15) { File.umask(2**64) }
show(16) { File.umask(m); File.umask(0o022) }
show(17) { File.dirname("/a/b/c/") }
show(18) { File.dirname("a/b/c", m.tap { def m.to_int = 1 }) }
show(19) { File.new(path, File::APPEND).class }
show(20) { File.new(path, File::RDONLY).read }
show(21) { File.open(path, nil, nil) { |f| f.read } }
show(22) { File.open(path, File::RDONLY) { |f| f.write("x") } }
f = File.open(path)
show(23) { f.path.equal?(f.path) }
show(24) { f.path.frozen? }
io = Object.new; io.define_singleton_method(:to_io) { f }
show(25) { File.size(io) }
sp = Object.new; def sp.to_str = "/a/b"
show(26) { File.split(sp) }
pp_ = Object.new; def pp_.to_path = "/a/b"
show(27) { File.split(pp_) }
show(28) { File.truncate(path, "x") }
show(29) { File.open(path, "r+") { |g| g.truncate("x") } }
show(30) { File.open(path, "r+") { |g| g.read(2); g.truncate(1); g.pos } }
e = (raise "x" rescue $!)
show(33) { Object.new.instance_variable_get("bad") rescue [$!.name, $!.receiver.class] }
show(34) { Object.class_variable_get("bad") rescue [$!.name, $!.receiver] }
show(35) { Object.class_variable_get(:@@nope) rescue [$!.name, $!.receiver] }
class Named; def self.name = "CustomName"; end
show(36) { Named.nope rescue $!.message }
show(37) { Named.new.nope rescue $!.message }
md = Object.new; def md.to_int = 0o755
show(38) { Dir.mkdir(File.join(dir, "d"), md) }
show(39) { Dir.mkdir(File.join(dir, "e"), Object.new) }
show(40) { Dir.new(dir).each.size }
show(41) { Dir.new(dir).each_child.size }
show(42) { Dir.home.frozen? }
show(43) { ENV.clone(freeze: 1) }
ENV["ZR_PROBE"] = "1"
k = Object.new; def k.to_str = "ZR_PROBE"
show(44) { ENV.delete(k); ENV["ZR_PROBE"] }
f.close
require "fileutils"
FileUtils.rm_rf(dir)
