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

show("getwd class") { Pathname.getwd.class }
show("pwd agrees with Dir") { Pathname.pwd.to_s == Dir.pwd }
show("Pathname.glob class") { Pathname.glob("*").class }
