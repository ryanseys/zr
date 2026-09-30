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

show("absolute?") { [Pathname.new("/a").absolute?, Pathname.new("a").absolute?] }
show("relative?") { [Pathname.new("/a").relative?, Pathname.new("a").relative?] }
show("root?") { [Pathname.new("/").root?, Pathname.new("/a").root?, Pathname.new("").root?] }

