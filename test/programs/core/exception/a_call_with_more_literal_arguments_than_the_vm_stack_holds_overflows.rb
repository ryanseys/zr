# CRuby pushes the literal arguments of a call on its VM stack, so a call
# with more of them than the stack holds raises SystemStackError before
# the method runs (test_exception.rb, test_too_many_args_in_eval). A call
# with fewer, a splat, and an Array literal of any size work. The test
# runs with a 64 KiB VM stack (RUBY_THREAD_VM_STACK_SIZE): 8,192 words.
def literal_call(name, n) = "#{name}(#{(0...n).to_a.join(", ")})"
def many(*a) = a.size

begin
  eval literal_call("raise", 9_000)
rescue SystemStackError, ArgumentError => e
  p e.class, e.message
end
p eval(literal_call("many", 6_000))
p many(*Array.new(20_000))
p eval("[#{(0...20_000).to_a.join(", ")}]").size
begin
  eval literal_call("many", 9_000)
rescue SystemStackError => e
  p e.class
end
