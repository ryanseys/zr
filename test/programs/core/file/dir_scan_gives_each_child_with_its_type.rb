# ruby 4.1's Dir.scan and Dir#scan give each child, other than . and
# .., with its type as lstat gives it: :file, :directory, :link, :fifo
# and the rest. With a block, each name and type, then nil.
require "tmpdir"
Dir.mktmpdir("zrscan") do |d|
  Dir.mkdir(File.join(d, "sub"))
  File.write(File.join(d, "f.txt"), "x")
  File.symlink("f.txt", File.join(d, "ln"))
  File.symlink("missing", File.join(d, "dangling"))
  File.symlink("sub", File.join(d, "dirlink"))
  system("mkfifo", File.join(d, "pipe"))
  p Dir.scan(d).sort
  got = []
  p Dir.scan(d) { |name, type| got << [name, type] }
  p got.sort
  dir = Dir.new(d)
  p dir.scan.sort, dir.scan, dir.children
  dir.close
  p((dir.scan rescue [$!.class, $!.message]))
  p Dir.scan(d, encoding: "ASCII-8BIT").first[0].encoding
  p Dir.new(d, encoding: "ASCII-8BIT").scan.first[0].encoding, Dir.scan(d).first[0].encoding
  p((Dir.scan(File.join(d, "nope")) rescue [$!.class, $!.message.sub(d, "D")]))
  p((Dir.scan(File.join(d, "f.txt")) rescue [$!.class, $!.message.sub(d, "D")]))
  p((Dir.scan rescue [$!.class, $!.message]))
  p((Dir.scan(1) rescue [$!.class, $!.message]))
  p Dir.scan(File.join(d, "sub")), Dir.method(:scan).arity, Dir.instance_method(:scan).arity
  p Dir.scan(Pathname(d)).size if defined?(Pathname)
  e = Dir.new(d)
  e.read
  p e.scan.size
end
