# Files, stat, glob and fnmatch under TMPDIR.
root = "#{ENV["TMPDIR"] || "/tmp"}/ze0_glob_#{Process.pid}"
Dir.mkdir(root)
Dir.mkdir("#{root}/a"); Dir.mkdir("#{root}/a/b"); Dir.mkdir("#{root}/.hid")
File.write("#{root}/x.rb", ""); File.write("#{root}/y.txt", ""); File.write("#{root}/a/z.rb", ""); File.write("#{root}/a/b/w.rb", ""); File.write("#{root}/.hid/h.rb", ""); File.write("#{root}/.dot.rb", "")
Dir.chdir(root) do
  p Dir.glob("*")
  p Dir.glob("*.rb")
  p Dir.glob("**/*.rb")
  p Dir["**/*.rb", "*.txt"]
  p Dir.glob("a/**/*")
  p Dir.glob("**/")
  p Dir.glob("{x,y}.*")
  p Dir.glob("*", File::FNM_DOTMATCH)
  p Dir.glob("a/*")
  p Dir.glob("nope/*")
  p Dir.glob("**/*.rb", base: "a")
  p Dir.glob("*.rb").map { |f| File.basename(f) }
  p Dir.glob("[xy].*")
  p Dir.glob("?.rb")
end
p Dir.glob("#{root}/*.rb").map { |f| File.basename(f) }
p File.fnmatch("*.rb", "a.rb"), File.fnmatch("*.rb", "a/b.rb"), File.fnmatch("*.rb", "a/b.rb", File::FNM_PATHNAME)
p File.fnmatch("**/*.rb", "a/b/c.rb", File::FNM_PATHNAME), File.fnmatch("**/*.rb", "c.rb", File::FNM_PATHNAME)
p File.fnmatch("*", ".hidden"), File.fnmatch("*", ".hidden", File::FNM_DOTMATCH), File.fnmatch("[a-c]x", "bx"), File.fnmatch("[!a-c]x", "bx")
p File.fnmatch("a?c", "abc"), File.fnmatch("A*", "abc", File::FNM_CASEFOLD), File.fnmatch("\\*", "*"), File.fnmatch("\\*", "a"), File.fnmatch("{a,b}c", "bc", File::FNM_EXTGLOB), File.fnmatch("{a,b}c", "bc")
p File.fnmatch?("a/*", "a/.b", File::FNM_PATHNAME), File.fnmatch?("a/*", "a/.b", File::FNM_PATHNAME | File::FNM_DOTMATCH)
system("rm", "-r", root)

s = File.stat("/tmp")
p s.class, s.directory?, s.file?, s.ftype, s.mode.to_s(8), s.size.class, s.mtime.class, s.nlink.class, s.ino.class
begin; File.stat("/nope"); rescue => e; p e.class, e.message; end
p File.realpath("/tmp")
begin; File.realpath("/nope"); rescue => e; p e.message; end
p File.realpath("tmp", "/private")
p File.symlink?("/tmp"), File.symlink?("/private/tmp"), File.symlink?("/nope")
p File.lstat("/tmp").symlink?
p (File.stat("/tmp") <=> File.stat("/private/tmp")), s.inspect.start_with?("#<File::Stat dev=0x")

class A; def x = 1; X = 2; @iv = 3; @@cv = 4; def self.s = 5; end
module M; def self.m = 6; end
A.include(M)
B = A.dup
p B.name, B.superclass, B.new.x, B::X, B.instance_variable_get(:@iv), B.class_variable_get(:@@cv), B.ancestors.first(3)
p B.s
C = A.clone
p C.s, C.name
p A.clone.name
N = M.dup
p N.m, N.name
p A.new.is_a?(B), B.new.is_a?(A)
B.class_eval { def y = 9 }
p A.new.respond_to?(:y)

def target(*a, **k) = [a, k]
ruby2_keywords def fwd(*a) = target(*a)
p fwd(1, k: 2)
def plain(*a) = target(*a)
p plain(1, k: 2)
class C
  def t(*a, **k) = [a, k]
  def f(*a) = t(*a)
  ruby2_keywords :f
  def g(*a, &b) = t(*a, &b)
  ruby2_keywords(:g)
end
p C.new.f(1, x: 1)
p C.new.g(2, y: 2)
p C.new.f(3)
p C.new.f(4, {z: 5})
h = { q: 1 }
p fwd(5, **h)
p h
p "é".succ, "aé".succ, "éz".succ, "z→".succ, "ÿ".succ, "→".succ, "a→z".succ, "9é".succ, "é9".succ, "z9é".succ, "漢".succ, "1漢".succ, "漢z".succ, "az".succ, "zz".succ, "a9".succ, "Zz".succ, "1.9".succ, "-".succ, "".succ, "a-z".succ, "9-z".succ, "az".next
s = +"é"; s.succ!; p s
