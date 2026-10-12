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

show("ancestors") { Pathname.ancestors }
show("own singleton") { Pathname.singleton_methods(false).sort }
show("own instance count") { Pathname.instance_methods(false).size }
show("constants") { Pathname.constants.sort }
show("VERSION") { Pathname::VERSION.match?(/\A\d+\.\d+\.\d+/) }
show("SEPARATOR_PAT") { Pathname::SEPARATOR_PAT }
# `#path` is PROTECTED in ruby; see tests/gaps/builtin_protected_rows.rb.
show("Kernel#Pathname is private") { Kernel.private_instance_methods(false).include?(:Pathname) }

