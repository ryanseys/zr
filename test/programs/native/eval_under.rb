# The program carries the compiler and writes its own code.
X = "top"

class M
  Y = "inM"
end

M.class_eval("Z = 1; p Y; p X; def foo = 'foo'; p self; p Module.nesting")
p M::Z, M.new.foo

obj = Object.new
obj.instance_eval("def bar = 'bar'; p self.class; p Module.nesting; W = 9")
p obj.bar, Object.const_defined?(:W)

p M.class_eval("1 + 1"), M.module_eval("2 + 2")
p M.class_eval("self"), obj.instance_eval("self").equal?(obj)
p [1, 2, 3].instance_eval("size")

M.class_eval { def block_form = "block" }
p M.new.block_form
p M.class_eval { self }
p obj.instance_eval { self }.equal?(obj)

begin
  M.class_eval
rescue ArgumentError => e
  p e.message
end
begin
  M.class_eval(1)
rescue TypeError => e
  p e.message
end
begin
  M.class_eval("1") { }
rescue ArgumentError => e
  p e.message
end
begin
  obj.instance_eval
rescue ArgumentError => e
  p e.message
end

def in_a_method
  eval("__method__")
end
p in_a_method, eval("__method__")

def raising
  eval("raise 'boom'")
rescue RuntimeError => e
  p e.backtrace.first.sub(%r{\A.*/}, "")
end
raising

begin
  Object.class_eval("\n\nraise 'late'", "somewhere.rb", 10)
rescue RuntimeError => e
  p e.backtrace.first
end

outer = 1
begin
  Object.class_eval("p outer")
  Object.new.instance_eval("p outer")
  eval("outer = 2")
  p outer
  eval("invented = 9")
  p defined?(invented)
end

def a_method
  n = 1
  [0].each { eval("n = 5") }
  [0].each { [0].each { eval("n += 1") } }
  p n, eval("defined?(n)")
end
a_method

counter = 3
1.times { eval("counter += 1") }
p counter

eval("'hello' =~ /l(l)o/")
p $~ && $~[0], $1
"xyz" =~ /y/
p eval("$~[0]"), eval("$&")

def a_match
  eval("'abc' =~ /b/")
  p $~[0]
end
a_match

held = binding
eval("'qqq' =~ /q+/", held)
p $~[0]
