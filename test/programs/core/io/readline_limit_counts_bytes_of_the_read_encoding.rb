# A limit counts bytes of the encoding that a line reads in, and a line
# ends on a whole character: in UTF-32 a separator's zero bytes still
# count toward it, and a stream that converts counts the converted bytes.
require "tmpdir"
Dir.mktmpdir do |dir|
  path = File.join(dir, "t")
  File.open(path, "w+b:utf-32le") do |f|
    f.write("0123456789")
    f.rewind
    p f.readline(3).bytesize, f.readline(4).bytesize, f.readline(5).bytesize, f.gets(nil, 2).bytesize
  end
  File.open(path, "w+:utf-8:utf-32le") do |f|
    f.write("0123456789")
    f.rewind
    p f.readline(4).bytesize, f.readline(3).bytesize, f.readline(9).bytesize, f.gets(nil, 5).bytesize
  end
  File.open(path, "w+:utf-8:utf-16be") do |f|
    f.write("ab\ncd\n")
    f.rewind
    p f.readline(1), f.readline(2), f.gets, f.gets(3)
  end
  File.open(path, "w+:utf-8") do |f|
    f.write("Test\nok\u{bf}ok\n")
    f.rewind
    p f.readline("\u{bf}"), f.readline("\u{bf}")
  end
  File.open(path, "w+:utf-32le:euc-jp") do |f|
    f.write("0123456789")
    f.rewind
    p f.readline(4).bytesize, f.readline(3).bytesize
  end
  # A wide encoding ends a line on its separator's whole last character,
  # never on a byte of another character that has the same value.
  File.open(path, "w+b:utf-32be") do |f|
    f.write("x\ny\n")
    f.rewind
    p f.each_line(5).map(&:bytesize)
    f.rewind
    p f.each_line("y".encode("utf-32be"), 3).map(&:bytesize)
  end
  File.open(path, "w+b:utf-16be") do |f|
    f.write("ਊ\n")
    f.rewind
    p f.each_line(2).map(&:bytesize)
  end
end
