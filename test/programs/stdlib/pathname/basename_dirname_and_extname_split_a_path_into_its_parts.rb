# `Pathname` is reachable with NO require: ruby 4.0 loads `pathname.so` before
# the first line. This covers the whole surface -- the path ALGEBRA, which is
# pure string work and never touches disk, and the delegations, which must
# answer exactly what the same `File`/`Dir` call answers.

require "pathname"   # a no-op here and in ruby 4.0: the class is already there
require "tmpdir"

def show(label)
  puts "#{label}: #{yield.inspect}"
rescue Exception => e # rubocop:disable Lint/RescueException
  puts "#{label}: #{e.class}: #{e.message}"
end

show("basename") { Pathname.new("/a/b.rb").basename.to_s }
show("basename suffix") { Pathname.new("/a/b.rb").basename(".rb").to_s }
show("dirname") { Pathname.new("/a/b.rb").dirname.to_s }
show("extname") { Pathname.new("/a/b.rb").extname }
show("sub_ext") { Pathname.new("a/b.rb").sub_ext(".txt").to_s }
show("sub_ext none") { Pathname.new("a/b").sub_ext(".txt").to_s }
show("sub_ext empty") { Pathname.new("a/b.rb").sub_ext("").to_s }
show("split") { Pathname.new("/a/b").split.map(&:to_s) }
show("split root") { Pathname.new("/").split.map(&:to_s) }
show("sub") { Pathname.new("/a/b").sub("a", "z").to_s }
show("sub block") { Pathname.new("/a/b").sub(/a/) { |m| m.upcase }.to_s }
show("expand_path") { Pathname.new("b").expand_path("/a").to_s }
show("fnmatch") { Pathname.new("a/b.rb").fnmatch("*/*.rb") }
show("fnmatch?") { Pathname.new("a/b.rb").fnmatch?("*.rb") }

