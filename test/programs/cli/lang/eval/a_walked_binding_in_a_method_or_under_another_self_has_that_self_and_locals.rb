# The tree-walking interpreter (ZR_EVAL=walk) gives `binding` in a string
# the self and the locals that ruby gives: a method, a singleton method
# and a class body that the string defines have their own, and a block
# under another self keeps the string's locals with that self.
x = 2
o = Object.new # rubocop:disable Lint/UselessAssignment -- the strings read it
p eval(<<~RUBY)
  def probe(a) = (b = a + 1; binding)
  s = probe(1)
  [s.local_variables.sort, s.local_variable_get(:b), s.receiver.equal?(self)]
RUBY
p eval("def o.probe = binding; s = o.probe; [s.local_variables, s.receiver.equal?(o)]")
p eval("b = class WalkedBody; k = 1; binding; end; [b.local_variables, b.receiver]")
p eval("y = 1; b = o.instance_eval { binding }; [b.local_variables.sort, b.receiver.equal?(o), b.local_variable_get(:x)]")
p eval("y = 3; binding").local_variable_get(:y)
p x
