require "coverage"
path = File.join(Dir.pwd, "covered.rb")
File.write(path, <<~SRC)
  x = 1
  if x > 0
    y = 2
  else
    w = 4
  end
  def m(a)
    [a].each do |i|
      puts i
    end
  end
  begin
    z = 1
  rescue => e
    e2 = 2
  ensure
    e3 = 3
  end
  q = 1 if false
SRC
p Coverage.line_stub(path)
iseq = RubyVM::InstructionSequence.compile_file(path)
p iseq.trace_points.select { |_, type| type == :line }.map(&:first)
iseq.each_child { |child| p [child.label, child.first_lineno, child.trace_points.select { |_, type| type == :line }.map(&:first)] }
