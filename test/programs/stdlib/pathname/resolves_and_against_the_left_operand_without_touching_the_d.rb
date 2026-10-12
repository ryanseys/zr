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

# `#+` resolves `.` and `..` against the LEFT operand's components, without
# ever asking the filesystem.
show("plus") { (Pathname.new("/a") + "b").to_s }
show("plus absolute") { (Pathname.new("/a") + "/b").to_s }
show("plus dot") { (Pathname.new("a") + ".").to_s }
show("plus dotdot") { (Pathname.new("a/b") + "..").to_s }
show("plus dotdot deep") { (Pathname.new("a/b/c") + "../../d").to_s }
show("plus empty left") { (Pathname.new("") + "b").to_s }
show("plus root") { (Pathname.new("/") + "a").to_s }
show("plus trailing sep") { (Pathname.new("a/") + "b").to_s }
show("plus both relative") { (Pathname.new("a/b") + "c/d").to_s }
show("div") { (Pathname.new("a") / "b").to_s }
show("plus Pathname") { (Pathname.new("a") + Pathname.new("b")).to_s }
show("join") { Pathname.new("/a").join("b", "c").to_s }
show("join none") { Pathname.new("/a").join.to_s }
show("join absolute wins") { Pathname.new("/a").join("b", "/c").to_s }
show("parent") { Pathname.new("/a/b").parent.to_s }
show("parent relative") { Pathname.new("a").parent.to_s }
show("parent root") { Pathname.new("/").parent.to_s }

