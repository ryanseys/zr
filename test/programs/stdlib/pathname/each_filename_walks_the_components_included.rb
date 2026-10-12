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

show("each_filename") { Pathname.new("/a/b/c").each_filename.to_a }
show("each_filename dotdot") { Pathname.new("a/b/../c").each_filename.to_a }
show("ascend") { Pathname.new("/a/b/c").ascend.map(&:to_s) }
show("ascend relative") { Pathname.new("a/b").ascend.map(&:to_s) }
show("ascend block") { r = []; Pathname.new("a/b").ascend { |x| r << x.to_s }; r }
show("descend") { Pathname.new("/a/b/c").descend.map(&:to_s) }
show("descend relative") { Pathname.new("a/b").descend.map(&:to_s) }

