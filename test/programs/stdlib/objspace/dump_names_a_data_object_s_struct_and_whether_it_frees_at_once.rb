# ObjectSpace.dump of a core T_DATA object names its rb_data_type_t, and
# ruby 4.1 says when that type does not free at once.
require "objspace"
def t(label)
  p [label, yield]
rescue Exception => e
  p [label, e.class, e.message.gsub(/0x\h+/, "0x")]
end
dumps = [Thread.current, binding, ObjectSpace::WeakMap.new, Queue.new, Thread::SizedQueue.new(1), Encoding::UTF_8, proc {}, method(:p), Mutex.new, Time.now, Random.new, [1].each, caller_locations(0).first, 1..2]
t(:dumps) { dumps.map { |o| d = ObjectSpace.dump(o); [d[/"type":"[A-Z]+"/], d[/"struct":"[^"]*"/], d[/"free_immediately":\w+/]] } }
