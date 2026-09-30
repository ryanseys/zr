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

# Construction.
show("new") { Pathname.new("/a/b").to_s }
show("new from Pathname") { Pathname.new(Pathname.new("a")).to_s }
show("new frozen arg") { Pathname.new("a".freeze).to_s }
show("new null byte") { Pathname.new("a\0b") }
show("new Integer") { Pathname.new(1) }
show("new no args") { Pathname.new }
show("Kernel#Pathname") { Pathname("/x").class }

