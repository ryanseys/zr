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

class Zone
  def to_str
    "+01:00"
  end
end
p Time.at(0).getlocal(Zone.new).utc_offset
p Time.at(0).localtime(Zone.new).utc_offset
t = Time.at(0)
t.localtime(Zone.new)
p t.utc_offset
