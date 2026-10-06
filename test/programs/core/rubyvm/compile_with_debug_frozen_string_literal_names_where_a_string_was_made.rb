# RubyVM::InstructionSequence.compile's debug_frozen_string_literal: a
# frozen String literal keeps where it was made, and a FrozenError names it.
opt = { frozen_string_literal: true, debug_frozen_string_literal: true }

str = RubyVM::InstructionSequence.compile('_="foo-1"', "test.rb", "test.rb", 1, **opt).eval
p [str, str.frozen?]
begin
  str << "x"
rescue FrozenError => e
  p e.message
end

ary = RubyVM::InstructionSequence.compile('["foo"]', "test.rb", "test.rb", 1, **opt).eval
p [ary.first, ary.first.frozen?]
begin
  ary.first << "x"
rescue FrozenError => e
  p e.message
end

# The line is the literal's own.
two = RubyVM::InstructionSequence.compile("x = 1\n['a',\n 'b']", "two.rb", "two.rb", 5, **opt).eval
two.each do |s|
  s.upcase!
rescue FrozenError => e
  p e.message
end

# Each run of a site gives its one String.
iseq = RubyVM::InstructionSequence.compile('"same"', "s.rb", "s.rb", 1, **opt)
p iseq.eval.equal?(iseq.eval)

# Without the option, a frozen literal names no place.
plain = RubyVM::InstructionSequence.compile('"bar"', "test.rb", "test.rb", 1, frozen_string_literal: true).eval
begin
  plain << "x"
rescue FrozenError => e
  p e.message
end
