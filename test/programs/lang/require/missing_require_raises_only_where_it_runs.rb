# A require of a file that is not there raises LoadError where it runs,
# as in ruby; one that never runs costs nothing.
if false
  require "zz_missing_library_one"
end

def never_called = require("zz_missing_library_two")

require "zz_missing_library_three" if ENV["ZZ_NOT_SET_ANYWHERE"]

begin
  require "zz_missing_library_four"
rescue LoadError => e
  p [e.class, e.message, e.path]
end

puts "reached"
require_relative "zz_missing_relative_file"
puts "not reached"
