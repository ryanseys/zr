# StringIO 3.2.1 (ruby 4.1): a frozen StringIO still reads, and only the
# calls that change the stream raise FrozenError. A read cannot fill the
# stream's own String, pread checks in C's order, and gets with chomp
# skips a long separator.
require "stringio"
def t(label)
  p [label, yield]
rescue Exception => e
  p [label, e.class, e.message.gsub(/0x\h+/, "0x")]
end
f = StringIO.new("ab\ncd\n").freeze
t(:frozen_reads) { [f.pos, f.gets, f.lineno, f.read(1), f.pread(2, 0), f.string, f.closed?, f.eof?, f.size, f.external_encoding, f.tty?, f.sync, f.tell] }
%i[rewind close close_read close_write binmode].each { |m| t(m) { f.public_send(m) } }
t(:pos=) { f.pos = 0 }
t(:lineno=) { f.lineno = 0 }
t(:seek) { f.seek(0) }
t(:string=) { f.string = "x" }
t(:write) { f.write("x") }
t(:set_encoding) { f.set_encoding("UTF-8") }
t(:open_freeze) { StringIO.open("x") { |s| s.freeze; :ok } }
t(:getc_frozen) { StringIO.new("xyz").freeze.getc }
t(:ungetc_frozen) { s = StringIO.new(+"xyz").freeze; s.getc; s.ungetc("q"); s.string }
s = StringIO.new("hello")
t(:read_own) { s.read(1, s.string) }
t(:read_all_own) { s.read(nil, s.string) }
t(:pread_own) { s.pread(0, 0, s.string) }
t(:pread_neg_off) { StringIO.new("").pread(0, -10) }
t(:pread_write_only) { StringIO.new(+"", "w").pread(0, 0) }
t(:pread_array) { s.pread(3, 0, []) }
t(:pread_frozen_buf) { s.pread(1, 9, "x".freeze) }
t(:pread_zero_buf) { s.pread(0, 0, +"abc") }
t(:pread_eof) { s.pread(1, 9) }
sio = StringIO.new("abcde\r\nfghij\r\n" + "z" * 1024)
t(:gets_chomp) { [sio.gets("\r\n", chomp: true), sio.gets("\r\n", chomp: true), sio.pos] }
sio2 = StringIO.new("ab::cd::" + "y" * 2000)
t(:gets_chomp2) { [sio2.gets("::", chomp: true), sio2.gets("::", chomp: true), sio2.gets("::", chomp: false).size] }
