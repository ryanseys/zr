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

show("cleanpath") { Pathname.new("a/../b/./c//d").cleanpath.to_s }
show("cleanpath conservative") { Pathname.new("a/../b/./c//d").cleanpath(true).to_s }
show("cleanpath dot") { Pathname.new(".").cleanpath.to_s }
show("cleanpath empty") { Pathname.new("").cleanpath.to_s }
show("cleanpath dotdot") { Pathname.new("..").cleanpath.to_s }
show("cleanpath above root") { Pathname.new("/../a").cleanpath.to_s }
show("cleanpath trailing") { Pathname.new("a/").cleanpath.to_s }
show("cleanpath root") { Pathname.new("/").cleanpath.to_s }

