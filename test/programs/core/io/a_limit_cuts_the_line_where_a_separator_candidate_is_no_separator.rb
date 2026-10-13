# IO#gets(sep, limit) stops at the limit even when the byte there ends
# a candidate that is no whole separator (ruby bug #22342): a candidate
# that does not start on a character boundary, or that is too short.
require "tmpdir"

Dir.mktmpdir do |dir|
  path = File.join(dir, "f")
  lines = lambda do |*args, encoding: nil|
    File.open(path, encoding: encoding) do |f|
      out = []
      while (line = f.gets(*args))
        out << line
      end
      out
    end
  end

  euc = "\xa2\xa4\xa4\xa2\xa4\xa4\xa4\xa6\xa4\xa8\xa4\xaa".b
  File.binwrite(path, euc)
  rs = "\xa4\xa4".dup.force_encoding("euc-jp")
  p lines.(rs, encoding: "euc-jp").map(&:b)
  p lines.(rs, 3, encoding: "euc-jp").map(&:b)
  p lines.(rs, 1, encoding: "euc-jp").map(&:b)

  File.write(path, "\n\n\n")
  p lines.("\r\n", 1), lines.("\r\n", 2), lines.("\r\n", 3)

  File.write(path, "a\nb\nc\r\n")
  p lines.("\r\n", 1), lines.("\r\n", 2), lines.("\r\n", 10)

  File.write(path, "é\nü\n\nñ\n")
  p lines.("\r\n", 1), lines.("\r\n", 3)

  File.binwrite(path, "a\xA5\xA9b")
  p lines.("é", 3).map(&:b), lines.("é", 2).map(&:b), lines.("é").map(&:b)
end
