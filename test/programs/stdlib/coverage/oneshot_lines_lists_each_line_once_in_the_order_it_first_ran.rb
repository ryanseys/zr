require "coverage"

# oneshot_lines: each line that ran, once, in the order of its first run,
# for files the build compiled and files required at run time. A clear
# empties the lists, and a line that ran before is not listed again.
Coverage.start(oneshot_lines: true)
require_relative "pick"

dir = Dir.pwd
late = File.join(dir, "late.rb")
File.write(late, <<~RUBY)
  def late(x)
    if x > 0
      :pos
    else
      :non_pos
    end
  end

  def first_this
    :a
  end
  first_this
RUBY
require late

here = File.expand_path("pick.rb", __dir__)
first = Coverage.result(stop: false, clear: true)
p first.fetch(late)
p first.fetch(here)

pick(-1)
late(-1)
p Coverage.result(stop: false, clear: true).fetch(late)
late(1)
pick(1)
second = Coverage.result(stop: false, clear: true)
p second.fetch(late), second.fetch(here)
late(1)
late(-1)
p Coverage.result(stop: false, clear: true).fetch(late)

# The lines of a method that runs once, then another, then the first again.
loop_file = File.join(dir, "order.rb")
File.write(loop_file, <<~RUBY)
  def b = :b

  def a
    :a
  end

  b
  a
  [1, 2].each do |i|
    i
  end
  b
RUBY
require loop_file
p Coverage.result.fetch(loop_file)
