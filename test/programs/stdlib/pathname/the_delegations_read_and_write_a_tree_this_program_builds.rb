# `Pathname` is reachable with NO require: ruby loads `pathname.so` before
# the first line. This covers the whole surface -- the path ALGEBRA, which is
# pure string work and never touches disk, and the delegations, which must
# answer exactly what the same `File`/`Dir` call answers.

require "pathname"   # a no-op here and in ruby: the class is already there
require "tmpdir"

def show(label)
  puts "#{label}: #{yield.inspect}"
rescue Exception => e # rubocop:disable Lint/RescueException
  puts "#{label}: #{e.class}: #{e.message}"
end

# The delegations, over a tree this program builds.
Dir.mktmpdir do |tmp|
  root = Pathname.new(tmp)
  file = root + "hello.txt"
  file.write("hello\nworld\n")
  sub = root + "sub"
  sub.mkpath
  (sub + "deep").mkpath
  (sub + "deep" + "leaf.txt").write("leaf")

  show("write returns count") { (root + "w.txt").write("abcd") }
  show("read") { file.read }
  show("read n") { file.read(5) }
  show("binread") { file.binread(5) }
  show("readlines") { file.readlines }
  show("each_line") { r = []; file.each_line { |l| r << l }; r }
  show("open block") { file.open { |f| f.read(5) } }
  show("size") { file.size }
  show("size?") { [file.size?, (root + "empty").tap { |p| p.write("") }.size?] }
  show("zero?") { (root + "empty").zero? }
  show("empty? file") { (root + "empty").empty? }
  show("empty? dir") { [(root + "sub" + "deep").empty?, sub.empty?] }
  show("exist?") { [file.exist?, (root + "nope").exist?] }
  show("file?") { [file.file?, sub.file?] }
  show("directory?") { [file.directory?, sub.directory?] }
  show("ftype") { [file.ftype, sub.ftype] }
  show("readable?") { file.readable? }
  show("writable?") { file.writable? }
  show("executable?") { file.executable? }
  show("symlink?") { file.symlink? }
  show("stat class") { file.stat.class }
  show("lstat class") { file.lstat.class }
  show("mtime class") { file.mtime.class }
  show("atime class") { file.atime.class }
  show("ctime class") { file.ctime.class }
  show("chmod") { file.chmod(0o600) }
  show("mode after chmod") { format("%o", file.stat.mode & 0o777) }
  show("truncate") { f = (root + "t.txt"); f.write("abcdef"); f.truncate(3); f.read }
  show("rename") do
    f = (root + "old.txt")
    f.write("x")
    f.rename((root + "new.txt").to_s)
    [(root + "old.txt").exist?, (root + "new.txt").read]
  end
  show("delete") { f = (root + "gone.txt"); f.write("x"); f.delete; f.exist? }
  show("make_symlink") do
    link = root + "link"
    link.make_symlink(file.to_s)
    [link.symlink?, link.readlink.to_s == file.to_s]
  end
  show("make_link") do
    link = root + "hard"
    link.make_link(file.to_s)
    [link.exist?, link.symlink?]
  end
  show("realpath class") { file.realpath.class }
  show("realdirpath class") { file.realdirpath.class }
  show("children classes") { root.children.map(&:class).uniq }
  show("children sorted") { sub.children.map { |c| c.basename.to_s }.sort }
  show("children bare") { sub.children(false).map(&:to_s).sort }
  show("each_child") { r = []; sub.each_child { |c| r << c.basename.to_s }; r.sort }
  show("entries sorted") { sub.entries.map(&:to_s).sort }
  show("each_entry") { r = []; sub.each_entry { |c| r << c.to_s }; r.sort }
  show("glob") { root.glob("*.txt").map { |p| p.basename.to_s }.sort }
  show("glob block") do
    r = []
    root.glob("*.txt") { |p| r << p.basename.to_s }
    r.sort
  end
  show("find") { root.find.map { |p| p.relative_path_from(root).to_s }.sort }
  show("mkdir") { d = (root + "fresh"); d.mkdir; d.directory? }
  show("mkdir twice") { (root + "fresh").mkdir rescue "#{$!.class}: #{$!.message[/\A[^@]*/].strip}" }
  show("rmdir") { d = (root + "fresh"); d.rmdir; d.exist? }
  show("mkpath deep") { d = (root + "x" + "y" + "z"); d.mkpath; d.directory? }
  show("rmtree") { d = (root + "x"); d.rmtree; d.exist? }
  show("opendir") { root.opendir { |d| d.class } }
  show("mountpoint? tmp") { root.mountpoint? }
  show("mountpoint? root") { Pathname.new("/").mountpoint? }
end

