# An unknown constant raises "uninitialized constant <Name>". This
# test checks constant references that resolve to known names: a user
# class, a user constant, Math and ARGV.

# User-defined class.
class T_known_constants_Box
  def initialize(v); @v = v; end
  attr_reader :v
end

puts T_known_constants_Box.new(7).v          # 7

# User-defined constant.
N = 42
puts N                     # 42

# Built-in module-like receiver (Math).
puts Math.sqrt(16).to_i    # 4

# ARGV / STDOUT pass through.
puts ARGV.length           # 0
