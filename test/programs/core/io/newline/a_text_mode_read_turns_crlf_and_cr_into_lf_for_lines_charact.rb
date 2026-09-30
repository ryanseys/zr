# A text-mode read turns CRLF and a lone CR into LF, for lines,
# characters and a read of the whole stream. read(length) gives the bytes
# as they are.
path = "/tmp/zr_spec_newline.txt"
File.binwrite(path, "a\r\nb\rc\nd\r")
File.open(path, "rt") { |f| p f.read }
File.open(path, newline: :universal) { |f| p f.read }
File.open(path, universal_newline: true) { |f| p f.read }
File.open(path, "r", textmode: true) { |f| p f.read }
File.open(path, "rt") { |f| p [f.gets, f.gets, f.gets, f.gets, f.gets] }
File.open(path, "rt") { |f| p f.each_char.to_a }
File.open(path, "rt") { |f| p [f.read(2), f.read(3), f.read] }
File.delete(path)
