# rb_str_encode_ospath: on macOS a path that is neither binary nor UTF-8
# goes to open(2) as UTF-8, so the file's name on disk is UTF-8.
require "tmpdir"
Dir.mktmpdir do |dir|
  name = "ªa123".encode("ISO-8859-1")
  File.write(File.join(dir, name), "x")
  found = Dir.children(dir)
  p found.size, found.first.b == "ªa123".b
  File.open(File.join(dir, name)) { |f| p f.path.encoding, f.read }
end
