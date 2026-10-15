# Class#new and #allocate on a singleton class raise TypeError. A class's
# own singleton class is never initialized, so it raises that first; the
# singleton class of any other object is a singleton class.
def attempt(label)
  yield
rescue TypeError, NoMethodError => e
  puts "#{label}: #{e.class}: #{e.message}"
end

object_class = Object.new.singleton_class
class_class = Class.new.singleton_class
attempt("object new") { object_class.new }
attempt("object allocate") { object_class.allocate }
attempt("string allocate") { "s".singleton_class.allocate }
attempt("class new") { class_class.new }
attempt("class allocate") { class_class.allocate }
attempt("String's") { String.singleton_class.allocate }
attempt("twice") { class_class.singleton_class.allocate }
attempt("bound new") { Class.instance_method(:new).bind_call(class_class) }
attempt("module's") { Kernel.singleton_class.allocate }
