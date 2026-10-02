# Line reading as ruby's rb_io_getline_0 does it: paragraph mode skips
# leading newlines on a fresh stream, a separator that would start inside
# a character does not match, and a limit that runs out on a separator's
# last byte with no whole separator reads on to the next one.
require "tmpdir"

Dir.mktmpdir do |dir|
  path = File.join(dir, "f")
  read = ->(*args, **kw) { File.open(path) { |f| a = []; f.each_line(*args, **kw) { |l| a << l }; a } }

  File.write(path, "\n\n\na\n\nb\n")
  p File.open(path) { |f| f.gets("") }
  p read.(""), read.("", chomp: true)

  File.write(path, "\n\n\n")
  p read.("\r\n", 1), read.("\r\n", 2), read.("", 1)

  File.write(path, "a\nb\n")
  p read.("\r\n", 1), read.("\n", 1)

  File.binwrite(path, "a\xA5\xA9b")
  p read.("é", 3), read.("é", 3, chomp: true)
  File.binwrite(path, "a\x80")
  p read.("\x80"), read.("\x80", chomp: true)

  File.write(path, "é\nü\n\nñ\n\n\n日本語\n")
  p read.("\r\n", 1), read.("\n", 2)
end
