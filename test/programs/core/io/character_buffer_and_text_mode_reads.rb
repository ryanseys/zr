# A text-mode stream holds characters only while an ungetc has put some
# back: byte reads refuse them then. A character read takes one
# character, so the bytes after it read raw. An unfinished character at
# the end comes one byte at a time, and a wide or stateful stream turns
# CR LF into one LF.
require "tmpdir"

def t(label)
  p [label, yield]
rescue => e
  p [label, e.class, e.message]
end

Dir.chdir(Dir.mktmpdir) do
  File.write("tst", "foo")
  { readpartial: ->(f) { f.readpartial(2) }, read2: ->(f) { f.read(2) }, getbyte: ->(f) { f.getbyte },
    ungetbyte: ->(f) { f.ungetbyte(0) }, sysread: ->(f) { f.sysread(2) }, copy_stream: ->(f) { IO.copy_stream(f, "out") },
    sysseek: ->(f) { f.sysseek(2) } }.each do |label, op|
    open("tst", "r+t") do |f|
      f.ungetc(f.getc)
      t(label) { op.(f) }
      t(:then) { [f.getc, f.read] }
    end
  end
  open("tst", "r+t") do |f|
    f.ungetc(f.getc)
    t(:each_byte) { f.each_byte { |c| }; :ok }
  end
  open("tst", "r+t") do |f|
    f.ungetc(f.getc)
    t(:read_all) { f.read }
  end
  # ungetbyte puts back bytes, which byte reads take.
  open("tst", "rt") do |f|
    f.ungetbyte("x")
    t(:after_ungetbyte) { f.read(2) }
  end

  File.binwrite("tmp", "\xE3\x81")
  open("tmp", "rt:utf-8") do |f|
    t(:getc1) { f.getc.b }
    t(:getc2) { f.getc&.b }
    t(:getc3) { f.getc }
  end

  File.binwrite("ie", "a\rb\r\nc\n\e$B\x42\x22\e(B")
  File.binwrite("be", "\0a\0\r\0b\0\r\0\n\0c\0\n\x85\x35")
  t(:ie_be) { open("ie", "rt:iso-2022-jp:utf-16be", &:read).b }
  t(:be_ie) { open("be", "rt:utf-16be:iso-2022-jp", &:read).b }
  t(:ie_ej) { open("ie", "rt:iso-2022-jp:euc-jp", &:read).b }
  t(:be_u8) { open("be", "rt:utf-16be:utf-8", &:read).b }
  t(:ie_be_bin) { open("ie", "rb:iso-2022-jp:utf-16be", &:read).b }
end

r, w = IO.pipe("US-ASCII:UTF-8", universal_newline: true)
w << "a\r\n\r\n\r\ncdefgh"
w.close
t(:gets) { r.gets("") }
t(:getc) { r.getc }
t(:readpartial) { r.readpartial(10) }
