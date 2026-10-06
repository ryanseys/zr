# A stream opened with xml: :attr is one quoted attribute: the quote
# opens before its first bytes and closes when it closes, whatever the
# writes; an empty stream has no quotes. A stateful encoding takes its
# writes through its ASCII-compatible form, and its newline decorators
# work once.
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
open("x9", "w:iso-2022-jp:utf-8", xml: :attr) { |f| f.print "丂" }; p File.binread("x9")
open("x10", "wb:iso-2022-jp", xml: :attr) { |f| f.print '&<>"\''; f.puts "丂あ" }; p File.binread("x10")
open("x11", "w:euc-jp:utf-8", xml: :attr) { |f| f.print "丂" }; p File.binread("x11")
open("x12", "w:sjis:utf-8", xml: :attr) { |f| f.print "丂" }; p File.binread("x12")
open("x13", "w:iso-2022-jp") { |f| f.print "aあ"; f.print "いb"; f.print "う" }; p File.binread("x13")
open("x14", "w:iso-2022-jp", undef: :replace) { |f| f.print "éあ" }; p File.binread("x14")
open("x15", "w:iso-2022-jp", crlf_newline: true) { |f| f.print "あ\n" }; p File.binread("x15")
open("x16", "w:utf-16le", crlf_newline: true) { |f| f.print "a\n" }; p File.binread("x16")
open("x17", "w:utf-16le:euc-jp", crlf_newline: true) { |f| f.print "\xA4\xA2\n".force_encoding("EUC-JP") }; p File.binread("x17")
open("x18", "w:iso-2022-jp:euc-jp", undef: :replace) { |f| f.print "\xA4\xA2\n".force_encoding("EUC-JP") }; p File.binread("x18")
