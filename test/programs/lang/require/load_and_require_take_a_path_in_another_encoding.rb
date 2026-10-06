# load and require take a path in an encoding other than UTF-8: the system
# gets it as UTF-8, and the file runs and is listed under that name.
# File.realpath gives the path back in its own encoding.
require "tmpdir"
base = "test_load\u{3042 3044 3046 3048 304a}".encode(Encoding::Windows_31J)
Dir.mktmpdir do |dir|
  path = File.join(dir, base + ".rb")
  begin
    load(File.join(dir, base))
  rescue LoadError => e
    p [e.class, e.message.include?(base), e.message.encoding]
  end
  File.open(path, "w+b") { |t| t.puts "$stderr.puts 'ok'" }
  p path.encoding
  load(path)
  sub = File.join(dir, "あ" * 5).encode(Encoding::Windows_31J)
  Dir.mkdir(sub)
  req = File.join(sub, "foo.rb")
  File.write(req, "$:.push __FILE__\n")
  $:.clear
  p require(req)
  p [$:.last.encoding, $:.last == req]
  p require(req)
end
p File.realpath(Dir.pwd.encode(Encoding::Windows_31J)).encoding
