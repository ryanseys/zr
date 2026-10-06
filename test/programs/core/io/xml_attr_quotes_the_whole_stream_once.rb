# A stream opened with xml: :attr is one quoted attribute: the quote
# opens before its first bytes and closes when it closes, whatever the
# writes; an empty stream has no quotes.
require "tmpdir"
Dir.chdir(Dir.mktmpdir)
open("x0", "wb", xml: :attr) { |f| f.print '&<>"\''; f.puts "丂あ" }; p File.binread("x0")
open("x1", "wb", xml: :attr) {}; p File.binread("x1")
open("x2", "wb", xml: :attr) { |f| f.write("") }; p File.binread("x2")
open("x3", "wb:utf-16le", xml: :attr) { |f| f.print "a\""; f.print "b" }; p File.binread("x3")
open("x4", "wb:us-ascii", xml: :attr) { |f| f.print "&<>\"'"; f.puts "丂あ" }; p File.binread("x4")
open("x5", "w", xml: :text) { |f| f.print "<a>\""; f.print "&" }; p File.binread("x5")
f = File.open("x6", "wb", xml: :attr); f.print "q"; f.flush; p File.binread("x6"); f.close; p File.binread("x6")
open("x7", "w:iso-2022-jp", xml: :attr) { |f| f.print "a"; f.print "あ" }; p File.binread("x7")
open("x8", "wb", xml: :attr) { |f| f << "a" << "b"; f.puts; f.printf("%d", 5) }; p File.binread("x8")
