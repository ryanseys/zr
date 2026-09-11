# A class whose allocator CRuby undefines refuses `allocate`, and so does
# a subclass of it, unless the subclass gets an allocator of its own, as
# the classes Struct.new and Data.define make do. The constructors of
# those classes still build their objects.

def show(label)
  print label, ": "
  r = yield
  puts r.is_a?(Module) ? r : r.inspect.gsub(/0x\h+/, "X")
rescue => e
  puts "#{e.class}: #{e.message.gsub(/0x\h+/, "X")}"
end

[Proc, Method, UnboundMethod, Binding, Thread, Encoding, Float, Struct, Data].each do |k|
  show(k.name) { k.allocate }
  show("#{k.name} subclass") { Class.new(k).allocate }
end

show("Rational") { Rational.allocate }
show("Rational subclass") { Class.new(Rational).allocate }
show("Complex") { Complex.allocate }

show("Struct.new") { Struct.new(:a).allocate }
show("Struct.new subclass") { Class.new(Struct.new(:a)).allocate }
show("Data.define") { Data.define(:a).allocate }
show("Data.define subclass") { Class.new(Data.define(:a)).allocate }

show("Proc subclass new") { Class.new(Proc).new { 1 }.call }
show("Thread subclass new") { Class.new(Thread).new { 2 }.value }
show("Struct subclass new") { Class.new(Struct.new(:a)).new(3).a }
show("Data subclass new") { Class.new(Data.define(:a)).new(a: 4).a }
show("Rational") { Rational(1, 3) + 1 }
show("Complex") { Complex(1, 1) * 2 }

show("singleton") { Object.new.singleton_class.allocate }
show("singleton new") { Object.new.singleton_class.new }

__END__
Proc: TypeError: allocator undefined for Proc
Proc subclass: TypeError: allocator undefined for #<Class:X>
Method: TypeError: allocator undefined for Method
Method subclass: TypeError: allocator undefined for #<Class:X>
UnboundMethod: TypeError: allocator undefined for UnboundMethod
UnboundMethod subclass: TypeError: allocator undefined for #<Class:X>
Binding: TypeError: allocator undefined for Binding
Binding subclass: TypeError: allocator undefined for #<Class:X>
Thread: TypeError: allocator undefined for Thread
Thread subclass: TypeError: allocator undefined for #<Class:X>
Encoding: TypeError: allocator undefined for Encoding
Encoding subclass: TypeError: allocator undefined for #<Class:X>
Float: TypeError: allocator undefined for Float
Float subclass: TypeError: allocator undefined for #<Class:X>
Struct: TypeError: allocator undefined for Struct
Struct subclass: TypeError: allocator undefined for #<Class:X>
Data: TypeError: allocator undefined for Data
Data subclass: TypeError: allocator undefined for #<Class:X>
Rational: NoMethodError: undefined method 'allocate' for class Rational
Rational subclass: NoMethodError: undefined method 'allocate' for class #<Class:X>
Complex: NoMethodError: undefined method 'allocate' for class Complex
Struct.new: #<struct a=nil>
Struct.new subclass: #<struct a=nil>
Data.define: #<data a=nil>
Data.define subclass: #<data a=nil>
Proc subclass new: 1
Thread subclass new: 2
Struct subclass new: 3
Data subclass new: 4
Rational: (4/3)
Complex: (2+2i)
singleton: TypeError: can't create instance of singleton class
singleton new: TypeError: can't create instance of singleton class
