# A circular require warns under $VERBOSE with one Warning.warn: the
# message after a prefix written twice, then each frame the oldest
# first as ruby's old backtrace printer writes it, and a blank line. The
# require returns false.
require "tmpdir"
dir = File.realpath(Dir.mktmpdir)
File.write(File.join(dir, "circ_me.rb"), "p [:inner, require('circ_me')]\n")
$LOAD_PATH.push(dir)
calls = []
Warning.singleton_class.define_method(:warn) { |msg, category: nil| calls << msg.gsub(dir, "DIR").gsub(__FILE__, "MAIN") }
$VERBOSE = true
p require("circ_me")
$VERBOSE = false
p calls.size
first, *frames = calls.first.lines
p first.scan(" warning: ").size, first[/loading in progress.*/]
# The frames of the program's files; rubygems gives require frames of its own.
puts frames.grep(/DIR|MAIN/).grep_v(/'require'/)
p calls.first.end_with?("'\n\n")
# Without $VERBOSE, nothing.
File.write(File.join(dir, "circ_two.rb"), "p [:two, require('circ_two')]\n")
calls.clear
p require("circ_two"), calls
File.delete(File.join(dir, "circ_me.rb"), File.join(dir, "circ_two.rb"))
Dir.rmdir(dir)
