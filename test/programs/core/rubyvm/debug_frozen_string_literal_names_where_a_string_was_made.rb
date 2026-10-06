# With debug_frozen_string_literal, the FrozenError of a literal names the
# file and line that made it.
src = '_ = "foo-1"'
str = RubyVM::InstructionSequence.compile(src, "test.rb", "test.rb", 1, frozen_string_literal: true, debug_frozen_string_literal: true).eval
p str.frozen?
begin
  str << "x"
rescue FrozenError => e
  p e.message
end

# The line is the literal's own, also past the first.
src = "a = 1\nb = 2\n_ = \"bar\""
str = RubyVM::InstructionSequence.compile(src, "other.rb", "other.rb", 10, frozen_string_literal: true, debug_frozen_string_literal: true).eval
begin
  str.upcase!
rescue FrozenError => e
  p e.message
end
