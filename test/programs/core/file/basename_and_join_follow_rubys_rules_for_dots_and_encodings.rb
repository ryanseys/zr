# File.basename with ".*" keeps the leading dots of a name, and
# File.join gives the encoding of its parts: binary with none, else the
# first part's, as fs_enc_check takes it.
p File.basename("..", ".*")
p File.basename(".bashrc", ".*")
p File.basename("..a.b", ".*")
p File.basename("a.", ".*")
p File.basename("/x/y.tar.gz", ".*")
[Encoding::BINARY, Encoding::US_ASCII, Encoding::UTF_8, Encoding::EUC_JP, Encoding::ISO_8859_1, Encoding::Windows_31J].each do |e|
  p [e, File.join(*%w[a b].map { |s| s.dup.force_encoding(e) }).encoding]
end
p File.join.encoding
p File.join("a", "é").encoding
p File.join("a".b, "b").encoding
