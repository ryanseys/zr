# A write payload whose type the analysis does not know: `@wrk.pack("C*")` on
# an ivar that can be nil. The write puts the String that pack answers, not an
# empty payload. optcarrot's ROM#save_battery is exactly this shape.
require "stringio"

dir = "/tmp/spinel_write_payload_untyped"
if Dir.exist?(dir)
  Dir.children(dir).each { |e| File.delete("#{dir}/#{e}") }
  Dir.rmdir(dir)
end
Dir.mkdir(dir)

class Battery
  def initialize(n)
    @wrk = n > 0 ? (65..67).map { |a| a } : nil
  end

  def save(path)
    File.binwrite(path, @wrk.pack("C*"))
  end

  def save_text(path)
    File.write(path, @wrk.pack("C*"))
  end

  def into(io)
    io.write(@wrk.pack("C*"))
  end
end

b = Battery.new(1)

bin = "#{dir}/battery.sav"
p b.save(bin)
p File.read(bin)

txt = "#{dir}/battery.txt"
p b.save_text(txt)
p File.read(txt)

io = StringIO.new
b.into(io)
p io.string

Dir.children(dir).each { |e| File.delete("#{dir}/#{e}") }
Dir.rmdir(dir)
