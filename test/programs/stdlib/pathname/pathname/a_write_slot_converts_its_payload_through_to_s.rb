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

sio = StringIO.new
p sio.write(Payload.new)
p (sio << Payload.new).equal?(sio)
p sio.write(42)
p (sio << :sym).equal?(sio)
p sio.print(Payload.new, 1)
p sio.puts(Payload.new)
p sio.puts
result = sio.puts("assigned")
p result
class Nul
  def to_s
    "a\0b"
  end
end
p sio.print(Nul.new)
p sio.print(:sym, [1, 2])
class Plain
end
sio.puts(Plain.new)
p sio.string.sub(/0x[0-9a-f]+/, "0xADDR")
mixed = StringIO.new
[1, "a", :b].each { |x| mixed.puts(x) }
p mixed.string
File.open(file, "r+") { |f| p [f.pwrite(Payload.new, 1), File.read(file)] }
File.open(file, "w") { |f| p f.write_nonblock(Payload.new) }
p File.read(file)
p File.write(pl, Payload.new)
p File.write(pl, 42, mode: "a")
p File.write(pl, :sym, 2)
p File.read(file)
def payload(nul)
  nul ? "a\0b" : Payload.new
end
p File.write(pl, payload(true))
p File.size(file)
p File.write(pl, payload(false))
