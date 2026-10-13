# ruby 4.1 writes Pathname's name helpers in pathname.c: they take only a
# String with no NUL byte, report C parameters, and two of them give the
# path itself back when it needs no change. SEPARATOR_PAT and
# SEPARATOR_LIST are gone.
def show
  p yield
rescue => e
  p [e.class, e.message]
end

pn = Pathname.new("x")
show { Pathname.constants.sort }
show { %i[sub_ext root? absolute?].map { |m| [m, Pathname.instance_method(m).parameters] } }
show { %i[same_paths? has_separator? chop_basename split_names has_trailing_separator? add_trailing_separator del_trailing_separator].map { |m| [m, Pathname.private_instance_methods(false).include?(m), Pathname.instance_method(m).arity] } }

["/a/b//", "a/b", "/a", "/", "//", "////x", ".", "..", "a", "a/", ""].each do |s|
  show { [s, pn.send(:chop_basename, s), pn.send(:split_names, s), pn.send(:has_trailing_separator?, s), pn.send(:has_separator?, s)] }
end
["a", "a/", "a//", "/", "///", "//a//", ""].each do |s|
  add = pn.send(:add_trailing_separator, s)
  del = pn.send(:del_trailing_separator, s)
  show { [s, add, add.equal?(s), del, del.equal?(s)] }
end
show { [pn.send(:same_paths?, "/a", "/a"), pn.send(:same_paths?, "/A", "/a")] }

show { pn.send(:chop_basename, 1) }
show { pn.send(:split_names, nil) }
show { pn.send(:has_separator?, :sym) }
show { pn.send(:same_paths?, "a", 1) }
show { pn.send(:add_trailing_separator, "a\0b") }
show { pn.send(:del_trailing_separator, "a/".encode("UTF-16LE")) }

["a.rb", "a.rb/", ".bashrc", "foo.", "a.b.c", "dir.d/file", "/x.y/z", ""].each do |s|
  show { [s, Pathname.new(s).sub_ext(".txt")] }
end
["/", "//", "/a", "a", "", "./", "/.", "."].each do |s|
  show { [s, Pathname.new(s).root?, Pathname.new(s).absolute?, Pathname.new(s).relative?] }
end

odd = Pathname.new("a")
odd.instance_variable_set(:@path, 3)
show { odd.root? }
odd.instance_variable_set(:@path, "a\0")
show { odd.absolute? }

show { Pathname.new("/usr/bin/../lib/./x").cleanpath }
show { Pathname.new("a//b/../c/").cleanpath(true) }
show { Pathname.new("/a") + "../../b" }
show { Pathname.new("a/b").relative_path_from("a/c/d") }
show { Pathname.new("/a/b/c").descend.map(&:to_s) }
show { Pathname.new("/a/b/c/").ascend.map(&:to_s) }
show { Pathname.new("a/b").each_filename.to_a }
