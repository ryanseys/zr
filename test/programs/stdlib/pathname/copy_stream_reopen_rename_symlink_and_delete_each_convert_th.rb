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

copy = "#{dir}/b.txt"
p IO.copy_stream(pl, PathLike.new(copy))
p File.read(copy)
io = File.open("/dev/null", "r")
p io.reopen(PathLike.new(copy), "r").read
io.close
moved = "#{dir}/c.txt"
p File.rename(PathLike.new(copy), PathLike.new(moved))
p File.exist?(moved)
link = "#{dir}/link"
p File.symlink(PathLike.new(moved), PathLike.new(link))
p File.readlink(PathLike.new(link)) == moved
p File.delete(PathLike.new(link), PathLike.new(moved))
p File.exist?(moved)
