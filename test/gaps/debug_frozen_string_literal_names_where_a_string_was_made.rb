# With debug_frozen_string_literal, the FrozenError of a literal names the
# file and line that made it. zr does not keep that place.
src = '_ = "foo-1"'
str = RubyVM::InstructionSequence.compile(src, "test.rb", "test.rb", 1, frozen_string_literal: true, debug_frozen_string_literal: true).eval
p str.frozen?
begin
  str << "x"
rescue FrozenError => e
  p e.message
end
