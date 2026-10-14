# Kernel#puts sends puts to $stdout with the objects as given, any count
# of them. An object there with only a write gets Kernel's lines through
# that write. IO#puts gives a write that the program wrote every piece.
class Recorder
  attr_reader :calls

  def initialize = @calls = []

  def write(*) = 0

  def puts(*objects)
    @calls << objects
    nil
  end
end

recorder = Recorder.new
$stdout = recorder
puts
puts "one"
puts "a", "b"
puts ["x", ["y"]]
puts nil
$stdout = STDOUT
p recorder.calls

class Writer
  attr_reader :parts

  def initialize = @parts = []

  def write(*parts)
    @parts << parts
    parts.sum { |part| part.to_s.bytesize }
  end
end

writer = Writer.new
$stdout = writer
puts "one"
puts "two\n", 3
puts
puts []
$stdout = STDOUT
p writer.parts

reader, out = IO.pipe
def out.write(*parts)
  STDOUT.print "write #{parts.inspect}\n"
  super
end
out.puts "a"
out.puts "b\n", :c
out.puts
out.puts ["d", ["e"]]
out.close
p reader.read

begin
  Object.new.puts "x"
rescue NoMethodError => e
  puts e.message
end
p Kernel.private_method_defined?(:puts), STDOUT.respond_to?(:puts)
STDOUT.puts "direct"
STDOUT.puts "x", "y"
STDOUT.puts ["z"]
STDOUT.puts
$stdout.puts 1, nil
