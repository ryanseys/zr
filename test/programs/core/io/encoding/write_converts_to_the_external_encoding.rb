# A stream that names an external encoding writes in it, as do_writeconv
# converts: through UTF-8 to one that is not ASCII-compatible, and not at
# all where the encoding is binary.

path = "wenc.txt"
File.open(path, "w", encoding: "UTF-16LE") { |f| f.write "é" }
p File.binread(path)
File.open(path, "w:UTF-16LE") { |f| p f.print "é"; f << "a"; p f.write("bc") }
p File.binread(path)
File.open(path, "w", external_encoding: "EUC-JP") { |f| f.puts "日本" }
p File.binread(path)
File.open(path, "w:UTF-8") { |f| f.write "é".encode("EUC-JP") }
p File.binread(path)
begin
  File.open(path, "w:UTF-16LE") { |f| f.write "\xff".b }
rescue => e
  p e
end
File.open(path, "w:UTF-16LE") { |f| f.write "a".b; f.write "\xff" } rescue p $!
p File.binread(path)
File.open(path, "wb:UTF-16LE") { |f| f.write "é" }
p File.binread(path)
File.open(path, "w:EUC-JP:UTF-8") { |f| f.write "é" }
p File.binread(path)
File.open(path, "w:EUC-JP") { |f| f.write "é".encode("UTF-16LE") }
p File.binread(path)
File.open(path, "w") { |f| f.set_encoding("UTF-16BE"); f.printf("%s", "a"); f.putc "b" }
p File.binread(path)
File.open(path, "wb") { |f| f.write "é".encode("EUC-JP") }
p File.binread(path)
File.delete(path)

