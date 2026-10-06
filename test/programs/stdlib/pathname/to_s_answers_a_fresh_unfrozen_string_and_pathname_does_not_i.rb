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

# Identity and ordering. `Pathname` does NOT include Comparable, however much
# its `#<=>` suggests otherwise.
show("to_s") { Pathname.new("a").to_s }
show("to_s is a fresh String") { p1 = Pathname.new("a"); !p1.to_s.equal?(p1.to_s) }
show("to_s is unfrozen") { Pathname.new("a").to_s.frozen? }
show("mutating to_s leaves self") { p1 = Pathname.new("a"); p1.to_s << "X"; p1.to_s }
show("inspect") { Pathname.new("/a/b").inspect }
show("== self") { Pathname.new("a") == Pathname.new("a") }
show("== String") { Pathname.new("a") == "a" }
show("===") { Pathname.new("a") === Pathname.new("a") }
show("eql?") { Pathname.new("a").eql?(Pathname.new("a")) }
show("hash agrees with ==") { Pathname.new("a").hash == Pathname.new("a").hash }
show("<=>") { Pathname.new("a") <=> Pathname.new("b") }
show("<=> String") { Pathname.new("a") <=> "a" }
show("no Comparable") { Pathname.new("a") < Pathname.new("b") }
show("freeze") { p1 = Pathname.new("a"); p1.freeze; p1.frozen? }
show("fresh is unfrozen") { Pathname.new("a").frozen? }

