# Pathname is a builtin in ruby, and require "pathname" adds the rest.
require "pathname"

p defined?(Pathname)
a = Pathname.new("/a/b/c")
p a.to_s, a.basename.to_s, a.dirname.to_s, a.parent.to_s, a.extname
p a.absolute?, a.relative?, a.root?, Pathname.new("/").root?
p (a + "d").to_s, (a / "d").to_s, (Pathname.new("a") + "/b").to_s
p Pathname.new("a/b/../c/./d//e").cleanpath.to_s
p Pathname.new("/a/b/../c").cleanpath.to_s
p Pathname.new("../a").cleanpath.to_s
p Pathname.new("/a/b/c").relative_path_from("/a").to_s
p Pathname.new("/a/b/c").relative_path_from("/a/x/y").to_s
p Pathname.new("a/b").relative_path_from("a/b").to_s
p a.each_filename.to_a
p a.descend.map(&:to_s)
p a.ascend.map(&:to_s)
p Pathname.new("/a").join("b", "c").to_s, Pathname.new("/a").join("/b").to_s
p a.split.map(&:to_s)
p a.sub("b", "z").to_s, Pathname.new("a.rb").sub_ext(".c").to_s
p a == Pathname.new("/a/b/c"), a.eql?(Pathname.new("/a/b/c")), a <=> Pathname.new("/a/b/d")
p [Pathname.new("/a/c"), Pathname.new("/a/b")].sort.map(&:to_s)
p a.inspect, a.hash == Pathname.new("/a/b/c").hash
p Pathname("x").class, Pathname(a).equal?(a)
p Pathname.new("x").frozen?, Pathname.new("x").freeze.frozen?
p Pathname.new(__FILE__).exist?, Pathname.new(__FILE__).file?, Pathname.new("/").directory?
p Pathname.new(__FILE__).read.lines.first
p Pathname.new(__FILE__).each_line.first
p Pathname.new("/tmp").children.class, Pathname.new("/tmp").glob("*").class
p Pathname.new("/tmp").entries.map(&:to_s).include?(".")
p Pathname.pwd.class
begin
  Pathname.new("a\0b")
rescue ArgumentError => e
  p [e.class, e.message]
end
