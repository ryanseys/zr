# The universal newline decorator reads a UTF-16 stream after its
# conversion, so a CR and an LF of two bytes each are one line end.
require "tmpdir"
Dir.chdir(Dir.mktmpdir)
{ "be.crlf" => ["\0a\0\r\0\n\0b\0\r\0\n\0c\0\r\0\n", "utf-16be"],
  "le.crlf" => ["a\0\r\0\n\0b\0\r\0\n\0c\0\r\0\n\0", "utf-16le"],
  "be.cr" => ["\0a\0\r\0b\0\r\0c\0\r", "utf-16be"],
  "le.lf" => ["a\0\n\0b\0\n\0c\0\n\0", "utf-16le"] }.each do |name, (bytes, enc)|
  File.binwrite(name, bytes)
  p File.read(name, mode: "rt:#{enc}:utf-8")
  File.open(name, "rt:#{enc}:utf-8") { |f| p f.gets, f.getc, f.readlines }
end
File.binwrite("be", "\0a\0\r\0b\0\r\0\n\0c\0\n\x85\x35")
File.open("be", "rt:utf-16be:euc-jp") { |f| p f.read }
File.open("be", "rb:utf-16be:euc-jp") { |f| p f.read }
