# ruby's parser prints its warnings also for code that does not parse:
# an eval, a second eval of the same code and
# RubyVM::InstructionSequence.compile print them before the SyntaxError,
# at the level of $VERBOSE.
$stderr = $stdout
$VERBOSE = true
2.times do
  eval("1...\n2\nfoo(")
rescue SyntaxError => e
  p e.class
end
begin
  RubyVM::InstructionSequence.compile("1...\n2\nfoo(")
rescue SyntaxError
  p :iseq
end
$VERBOSE = false
begin
  eval("1...\n2\nfoo(")
rescue SyntaxError
  p :not_verbose
end
$VERBOSE = nil
begin
  eval("1...\n2\nfoo(")
rescue SyntaxError
  p :quiet
end
# The error's own message has no warnings in it.
$VERBOSE = true
begin
  eval("x = 1...\n2\n(", binding, "named.rb", 7)
rescue SyntaxError => e
  p e.message.include?("warning")
end
