# Marshal: a C (user class) record around a Struct gives the struct as that
# class when the class has as many members; ruby 4.1 names the class when
# the sizes differ.
U = Struct.new(:a)
T = Struct.new(:b)
W = Struct.new(:a, :b)
class V < U; end
class Plain; end
def load(label, bytes)
  p [label, Marshal.load(bytes)]
rescue Exception => e
  p [label, e.class, e.message]
end
struct_u = "S:\x06U\x06:\x06ai\x06"
load(:same_size, "\x04\bC:\x06T#{struct_u}".b)
load(:subclass, "\x04\bC:\x06V#{struct_u}".b)
load(:wider, "\x04\bC:\x06W#{struct_u}".b)
load(:plain, "\x04\bC:\x0APlain#{struct_u}".b)
load(:string_class, "\x04\bC:\x0BString#{struct_u}".b)
load(:array_to_struct, "\x04\bC:\x06T[\x06i\x06".b)
load(:module_wrap, "\x04\bC:\x06Um\x0BKernel".b)
