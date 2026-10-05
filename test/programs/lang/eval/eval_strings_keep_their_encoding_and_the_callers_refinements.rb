# An eval's code starts in its String's encoding; a magic comment counts
# only on the first line.
eval("X1 = 'π'".b)
p X1.encoding
eval("# encoding: UTF-8\nX2 = 'π'".b)
p X2.encoding
eval("# frozen_string_literal: true\n# encoding: UTF-8\nX3 = 'π'".b)
p X3.encoding, X3.frozen?
eval("# frozen_string_literal: true\nX4 = :π".b)
p X4.encoding, X4 == :π
eval("class E5; Vπ = 1; end".b)
p E5.constants, E5.constants.first.encoding
p E5.const_get("Vπ".b.to_sym)

# class_eval, module_eval and instance_eval run their string under the
# refinements of the call site, also through send.
class NamedClass; end
refinery = Module.new do
  refine NamedClass do
    def foo = "bar"
  end
end
r = []
Class.new do
  using refinery
  r << (send(:class_eval, "NamedClass.new.foo") rescue $!.class)
  r << (class_eval("NamedClass.new.foo") rescue $!.class)
  r << (module_eval("NamedClass.new.foo") rescue $!.class)
  r << (eval("NamedClass.new.foo") rescue $!.class)
  r << (send(:module_eval) { NamedClass.new.foo } rescue $!.class)
  r << (instance_eval("NamedClass.new.foo") rescue $!.class)
  r << (public_send(:instance_eval, "NamedClass.new.foo") rescue $!.class)
end
p r
p((NamedClass.class_eval("new.foo") rescue $!.class))

# __dir__ in an eval given a file name is that name's directory.
p eval("__dir__", nil, "foo.rb"), eval("__dir__", nil, "foo/bar.rb"), eval("__dir__", nil, "/abs/x.rb"), eval("__dir__")
p eval("[1].map { __dir__ }", nil, "a/b.rb")
p __dir__ == File.dirname(File.realpath(__FILE__))
