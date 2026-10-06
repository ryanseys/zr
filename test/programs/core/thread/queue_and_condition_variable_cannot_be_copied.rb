# A Queue and a ConditionVariable have no initialize_copy, so dup
# raises NoMethodError, and neither can be dumped.
[Thread::Queue.new, Thread::SizedQueue.new(1), Thread::ConditionVariable.new].each do |o|
  begin
    o.dup
  rescue NoMethodError => e
    p e.message
  end
  begin
    Marshal.dump(o)
  rescue TypeError => e
    p e.message
  end
end
