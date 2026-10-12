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

show("relative_path_from") { Pathname.new("/a/b/c").relative_path_from("/a/d").to_s }
show("relative_path_from same") { Pathname.new("/a/b").relative_path_from("/a/b").to_s }
show("relative_path_from below") { Pathname.new("a/b").relative_path_from("a").to_s }
show("relative_path_from above") { Pathname.new("a").relative_path_from("a/b/c").to_s }
show("relative_path_from mixed") { Pathname.new("a").relative_path_from("/b") }
show("relative_path_from dotdot base") { Pathname.new("a").relative_path_from("../b") }

