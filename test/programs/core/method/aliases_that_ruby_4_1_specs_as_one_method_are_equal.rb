# Methods that ruby defines with one C function are equal, also as
# Methods of their singletons: Regexp.escape and quote, FileTest and
# File's empty? and zero?, Syslog's reopen and open!. Each keeps its name.
require "syslog"
p Regexp.method(:escape) == Regexp.method(:quote), Regexp.method(:quote).original_name, Regexp.method(:quote).name
p FileTest.method(:zero?) == FileTest.method(:empty?), File.method(:zero?) == File.method(:empty?), FileTest.method(:zero?).original_name
p Syslog.method(:reopen) == Syslog.method(:open!), Syslog.method(:reopen).original_name
p Regexp.method(:escape).hash == Regexp.method(:quote).hash, Regexp.quote("a.b"), FileTest.zero?(__FILE__)
