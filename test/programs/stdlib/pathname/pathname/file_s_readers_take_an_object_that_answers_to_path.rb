require "pathname"
require "stringio"

dir = "/tmp/spinel_implicit_conversion_protocol_#{Process.pid}"
if Dir.exist?(dir)
  Dir.children(dir).each { |e| File.delete("#{dir}/#{e}") }
  Dir.rmdir(dir)
end
Dir.mkdir(dir)
file = "#{dir}/a.txt"
File.write(file, "abcdef\n")

class Conf
  attr_accessor :path

  def to_path
    @path
  end
end

class PathLike
  def initialize(path)
    @path = path
  end

  def to_path
    @path
  end
end

class StrLike
  def initialize(path)
    @path = path
  end

  def to_str
    @path
  end
end

class Both
  def initialize(path)
    @path = path
  end

  def to_path
    @path
  end

  def to_str
    "/nonexistent/#{@path}"
  end
end

pl = PathLike.new(file)
dl = PathLike.new(dir)
pn = Pathname.new(file)
DIR = dir
class Payload
  def to_s
    "payload"
  end
end

class Churn
  def initialize(n)
    @n = n
  end
  def to_path
    2000.times { "z" * 40 }
    "#{DIR}/churn#{@n}.txt"
  end
end

p File.exist?(pl)
p File.file?(pl)
p File.read(pl)
p File.basename(pl)
p File.dirname(pl) == dir
p File.extname(pl)
p File.expand_path(PathLike.new("x"), dir) == "#{dir}/x"
p File.size(pl)
p File.readlines(pl)
p File.readlines(pl, chomp: true)
p IO.read(pl)
p IO.readlines(pl)
lines = []
File.foreach(pl) { |l| lines << l }
p lines
p File.open(pl) { |f| f.read(3) }
p File.open(pl, "r") { |f| f.gets }
p File.join("a", PathLike.new("b"), "c")
p File.stat(pl).size
p File.exist?(StrLike.new(file))
p File.read(StrLike.new(file))
p File.exist?(Both.new(file))
conf = Conf.new
conf.path = file
p File.exist?(conf)
conf.path = nil
begin
  File.exist?(conf)
rescue TypeError => e
  p [e.class, e.message]
end
p File.atime(pl).class
p File.owned?(pl)
p File.realdirpath(PathLike.new("a.txt"), dl) == File.realpath(file)
p File.expand_path("a.txt", PathLike.new(dir)) == file
p File.absolute_path("a.txt", PathLike.new(dir)) == file
p File.utime(Time.at(0), Time.at(0), pl)
p File.join(["a", PathLike.new("b")], "c")
