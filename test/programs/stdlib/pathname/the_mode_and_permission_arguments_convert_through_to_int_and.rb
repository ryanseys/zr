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

class ReadMode
  def to_int
    File::RDONLY
  end
end

class ModeName
  def to_str
    "r"
  end
end
p File.open(pl, ReadMode.new) { |f| f.read(2) }
p File.open(pl, ModeName.new) { |f| f.read(2) }
p File.open(pl, mode: ReadMode.new) { |f| f.read(2) }
class CreateMode
  def to_int
    File::WRONLY | File::CREAT
  end
end
made = "#{dir}/made.txt"
File.open(made, CreateMode.new, 0600) { |f| f.write("m") }
p format("%o", File.stat(made).mode & 0777)
File.delete(made)
File.open(made, "w", 0600) { |f| f.write("m") }
p format("%o", File.stat(made).mode & 0777)
File.delete(made)
File.open(made, "w", perm: 0600) { |f| f.write("m") }
p format("%o", File.stat(made).mode & 0777)
File.delete(made)
File.open(made, mode: "w", perm: 0640) { |f| f.write("m") }
p format("%o", File.stat(made).mode & 0777)
File.delete(made)
File.open(made, File::WRONLY | File::CREAT, perm: 0600) { |f| p f.path == made }
p format("%o", File.stat(made).mode & 0777)
File.delete(made)
def maybe_perm(x)
  x ? 0600 : nil
end
File.open(made, "w", maybe_perm(false)) { |f| f.write("m") }
p format("%o", File.stat(made).mode & 0777)
File.open(made, "w", nil) { |f| p f.close_on_exec? }
begin
  File.open(made, "wx", 0600) { |f| f.write("!") }
rescue SystemCallError => e
  p e.class
end
p File.read(made)
File.delete(made)
begin
  File.open(made, "+", 0600)
rescue ArgumentError => e
  p e.message
end
begin
  File.open(made, "rx", 0600)
rescue ArgumentError => e
  p e.message
end
begin
  File.open(made, "ax")
rescue ArgumentError => e
  p e.message
end
File.open(made, "wx+", 0600) { |f| f.write("zz"); f.rewind; p f.read }
File.delete(made)
