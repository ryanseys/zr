# coverage.c and pty.c define module functions, so a class that
# includes the module has a private copy of each.
require "coverage"
require "pty"
p Coverage.private_instance_methods(false).sort, Coverage.instance_method(:result).arity
p Class.new { include Coverage; def ask = [state, running?] }.new.ask
p PTY.private_instance_methods(false).sort, PTY.method(:getpty), PTY.method(:spawn), PTY.instance_method(:getpty)
