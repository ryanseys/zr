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

class Fresh
  def initialize(n)
    @n = n
  end
  def to_path
    "seg" + @n.to_s
  end
end
bad = 0
2000.times do |i|
  r = File.join(Fresh.new(i), Fresh.new(i + 1), Fresh.new(i + 2))
  bad += 1 unless r == "seg#{i}/seg#{i + 1}/seg#{i + 2}"
end
p bad

class Loud
  def to_s
    2000.times { "z" * 40 }
    "PAY"
  end
end

p File.write(Churn.new(1), Loud.new)
File.rename(Churn.new(1), Churn.new(2))
p [File.exist?("#{dir}/churn1.txt"), File.exist?("#{dir}/churn2.txt")]
p File.expand_path(Churn.new(1), Churn.new(2)) == "#{dir}/churn2.txt#{dir}/churn1.txt"
File.delete("#{dir}/churn2.txt")
class Built
  def to_path
    b = ""
    50.times { b = b + "ab" }
    b
  end
end
bad = 0
2000.times { bad += 1 unless File.join(Built.new) == "ab" * 50 }
p bad
loop_a = ["x"]
loop_a << loop_a
begin
  File.join(loop_a)
rescue ArgumentError => e
  p e.message
end
