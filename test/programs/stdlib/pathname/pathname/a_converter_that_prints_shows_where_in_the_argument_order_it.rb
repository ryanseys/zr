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

# The rows below read this file, which the write rows left holding
# a converted payload rather than the bytes the setup wrote.
File.write(file, "payload")
sio = StringIO.new
class Noisy
  def initialize(n)
    @n = n
  end
  def to_s
    $stdout.print("[c#{@n}]")
    "<#{@n}>"
  end
end
$stdout.write(Noisy.new(5), Noisy.new(6))
puts
def named
  puts "named"
  "#{DIR}/named.txt"
end
File.write(named, Payload.new)
File.write("#{dir}/churn1.txt", "x")
File.rename(Churn.new(1), named)
p [File.exist?("#{dir}/churn1.txt"), File.read("#{dir}/named.txt")]
File.delete("#{dir}/named.txt")
class Wide
  def initialize(s)
    @s = s
  end
  def to_path
    ("y" * 3000).sub("y", @s)[0, 3]
  end
end
letters = ("a".."t").to_a
bad = 0
100.times do
  r = File.join(Wide.new("a"), Wide.new("b"), Wide.new("c"), Wide.new("d"), Wide.new("e"),
                Wide.new("f"), Wide.new("g"), Wide.new("h"), Wide.new("i"), Wide.new("j"),
                Wide.new("k"), Wide.new("l"), Wide.new("m"), Wide.new("n"), Wide.new("o"),
                Wide.new("p"), Wide.new("q"), Wide.new("r"), Wide.new("s"), Wide.new("t"))
  bad += 1 unless r == letters.map { |x| x + "yy" }.join("/")
end
p bad

def trace(label, value)
  puts label
  value
end
def trace_io(label, io)
  puts label
  io
end
p File.exist?(trace("arg", pl))
p trace_io("recv", sio).write(trace("arg", Payload.new))
class Announced
  def initialize(path)
    @path = path
  end
  def to_path
    puts "convert"
    @path
  end
end
def sideff(n)
  puts "sibling"
  n
end
announced = Announced.new(file)
p File.read(announced, sideff(4))
class Offset
  def to_int
    puts "convert"
    2
  end
end
off = Offset.new
p "abcdef"[off, sideff(3)]
class Spoken
  def to_s
    puts "convert"
    "payl"
  end
end
spoken = Spoken.new
File.open(file, "w") { |f| p f.write(spoken, sideff("Z")) }
p File.read(file)
