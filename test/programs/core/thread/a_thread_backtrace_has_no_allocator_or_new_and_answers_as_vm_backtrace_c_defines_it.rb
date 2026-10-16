# Thread::Backtrace (Init_vm_backtrace): the allocator stays, for
# Marshal, and raises; `new` is undefined; `clone` and `dup` are its own
# methods, and `initialize_copy` a private one.
def t(label)
  print label, ": "
  p yield
rescue Exception => e
  puts "#{e.class}: #{e.message}"
end
bt = Thread::Backtrace
t(:allocate) { bt.allocate }
t(:new) { bt.new }
t(:instance_methods) { bt.instance_methods(false).sort }
t(:private) { bt.private_instance_methods(false).sort }
t(:singleton) { bt.singleton_methods.sort }
t(:superclass) { bt.superclass }
t(:limit) { bt.limit }
t(:subclass_allocate) { Class.new(bt).allocate }
t(:respond_to_dup) { bt.method_defined?(:dup) }
t(:location_allocate) { Thread::Backtrace::Location.allocate }
