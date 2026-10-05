# A class with a prepended module still defines its own methods; a
# constant name that makes no Symbol raises EncodingError; and a frozen
# class refuses deprecate_constant.
def show(label)
  p [label, yield]
rescue StandardError, EncodingError => e
  p [label, e.class, e.message[/\A[^#]*/]]
end

own = Class.new { def foo; end }
own.prepend(Module.new)
copy = Class.new { def foo; end }.clone
copy.prepend(Module.new)
only = Class.new { prepend(Module.new { def foo; end }) }
[own, copy, only].each_with_index do |klass, i|
  show(i) { [klass.public_method_defined?(:foo, false), klass.method_defined?(:foo, false), klass.method_defined?(:foo)] }
end

show(:const_defined) { Math.const_defined?("\xC3") }
show(:const_get) { Math.const_get("\xC3") }
show(:deprecate) { Class.new { const_set(:A, 1) }.freeze.class_eval { deprecate_constant :A } }
