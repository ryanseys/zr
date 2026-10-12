# date_core.c's surface: VERSION, DateTime._strptime, Date.new through
# Class#new and Date#initialize, and no helper a program can see.
require "date"
p Date::VERSION.match?(/\A\d+\.\d+\.\d+/)
p DateTime._strptime("2001-02-03T04:05:06+07:00")
p DateTime._strptime("2001 3", "%Y %j"), DateTime._strptime("x", "%Y")
p Date.private_methods(false).sort - Class.private_instance_methods, DateTime.private_methods(false).sort - Class.private_instance_methods
p Date.private_instance_methods(false).sort, DateTime.private_instance_methods(false)
p Date.singleton_methods(false).include?(:new), DateTime.singleton_methods(false).include?(:_strptime)
p Date.method(:new).owner, Date.instance_method(:initialize).owner, DateTime.method(:new).owner
p Date.new(2001).instance_variables, DateTime.instance_variables
