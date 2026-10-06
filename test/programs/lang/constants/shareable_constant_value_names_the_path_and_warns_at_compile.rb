# A shareable constant that is not shareable names its path as written.
# RubyVM::InstructionSequence.compile prints the warnings of the magic
# comment when it compiles. A #freeze that does not freeze is an error.
B = Class.new
[
  "# shareable_constant_value: literal\nB::C = [\"Not \" + \"shareable\"]\n",
  "# shareable_constant_value: literal\n::TOPC = [\"a\" + \"b\"]\n",
  "# shareable_constant_value: literal\nmodule M; X = [\"a\" + \"b\"]; end\n",
  "# shareable_constant_value: literal\nB.itself::D = [\"a\" + \"b\"]\n"
].each do |code|
  eval(code)
rescue => e
  p [e.class, e.message]
end

$VERBOSE = true
RubyVM::InstructionSequence.compile("# shareable_constant_value: invalid-option\n1", "invalid.rb")
RubyVM::InstructionSequence.compile("nil # shareable_constant_value: true\n2", "ignored.rb")
$VERBOSE = false
RubyVM::InstructionSequence.compile("# shareable_constant_value: invalid-option\n1", "quiet.rb")

begin
  eval(<<~RUBY)
    # shareable_constant_value: experimental_everything
    o = Object.new
    def o.freeze = self
    E = [o]
  RUBY
rescue Ractor::Error => e
  p [e.class, e.message]
end
