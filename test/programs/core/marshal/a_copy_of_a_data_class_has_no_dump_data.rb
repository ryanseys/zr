# A copy of a class whose objects CRuby keeps as T_DATA (Class#dup) keeps
# the allocator, so with no marshal_dump its objects have no _dump_data.
DumpableCV = Thread::ConditionVariable.dup.tap { |c| c.class_eval { remove_method :marshal_dump } }
DumpableQ = Thread::Queue.dup.tap { |c| c.class_eval { remove_method :marshal_dump } }
DumpableM = Thread::Mutex.dup
[Thread::ConditionVariable.new, DumpableCV.new, DumpableQ.new, DumpableM.new, Class.new(Thread::Queue).new].each do |o|
  Marshal.dump(o)
  p :dumped
rescue TypeError => e
  p e.message.sub(/#<Class:0x\h+>/, "C")
end
Plain = Struct.new(:a).dup
p Marshal.load(Marshal.dump(Object.new.tap { _1.instance_variable_set(:@x, 1) })).instance_variable_get(:@x)
