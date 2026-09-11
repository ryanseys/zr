# fileutils defines methods from strings, so the program carries the
# compiler, and with it prism's polyfills. Each polyfill patches a core
# class only when a method is missing or reports other parameters than
# CRuby's, so none of them may fire.
require "fileutils"
require "strscan"

p String.ancestors.first(2), StringScanner.ancestors.first(2)
p Array.instance_method(:pack).parameters, String.instance_method(:unpack).parameters, String.instance_method(:unpack1).parameters
p "xyz".unpack1("a", offset: 1), "ab".unpack("C*") { |b| p b }

s = StringScanner.new("ab")
p s.scan_byte, s.pos, s.matched, s.peek_byte, s.scan_byte, s.scan_byte

__END__
[String, Comparable]
[StringScanner, Object]
[[:req, :fmt], [:key, :buffer]]
[[:req, :fmt], [:key, :offset]]
[[:req, :fmt], [:key, :offset]]
97
98
"y"
nil
97
1
"a"
98
98
nil
