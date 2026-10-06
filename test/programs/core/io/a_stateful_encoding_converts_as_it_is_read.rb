# A stream that converts a stateful encoding (ISO-2022-JP) converts as it
# reads, so a separator, getc and ungetc see the converted text.
require "tmpdir"
Dir.chdir(Dir.mktmpdir)
src = "before \e$B\x23\x30\x23\x31\e(B after".dup.force_encoding("iso-2022-jp")
File.binwrite("tmp", src)
s = File.open("tmp", "r:iso-2022-jp:euc-jp") { |f| f.gets("0".dup.force_encoding("euc-jp")) }
p s.encoding, s == src.encode("euc-jp")
File.binwrite("g", "\e$B\x23\x30\x23\x31\e(B")
File.open("g", "r:iso-2022-jp:euc-jp") { |f| p f.getc, f.getc, f.getc }
rs = "\e$B\x23\x30\e(B".dup.force_encoding("iso-2022-jp")
File.open("tmp", "r:iso-2022-jp:euc-jp") do |f|
  p f.gets(rs.encode("euc-jp", "iso-2022-jp"))
  f.ungetc("0")
  p f.read
end
File.open("tmp", "r:iso-2022-jp:euc-jp") { |f| p f.read, f.read.encoding }
