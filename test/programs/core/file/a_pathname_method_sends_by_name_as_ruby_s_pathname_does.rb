# Pathname is Ruby code in CRuby (pathname_builtin.rb), so its sends go
# by name: a program's prepend on File's singleton class, or an object's
# own is_a?, answers them.
require "pathname"

obj = Object.new
def obj.cleanpath = Pathname.new("/foo/baz")
def obj.is_a?(m) = m == Pathname
p Pathname.new("/foo/bar").relative_path_from(obj)
p Pathname.new("/foo/bar").relative_path_from("/foo/baz")
p Pathname("dirname/basename").split

seen = []
File.singleton_class.prepend(Module.new do
  define_method(:basename) { |*args| seen << args; super(*args) }
  def split(_arg) = nil
end)
begin
  Pathname("/").split
rescue TypeError => e
  p e
end
p Pathname("/a/b.rb").basename, seen
