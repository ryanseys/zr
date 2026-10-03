class C
  def a = 1
end

p C.method(:private).call
p C.method(:public).call
p C.method(:protected).call
p C.send(:private)
m = Module.new
p m.method(:module_function).call
def C.b = 2
C.class_eval { def c = 3 }
p C.public_method_defined?(:a), C.public_method_defined?(:c)
