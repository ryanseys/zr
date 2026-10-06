# A finalizer that waits for another thread runs only where a thread
# may switch, never inside the scheduler.
require "open3"

class Wrapper
  def initialize
    @stdin, @stdout, @stderr, @waiter = Open3.popen3("cat")
    ObjectSpace.define_finalizer(self, self.class.finalizer(@stdin, @stdout, @stderr, @waiter))
  end

  def self.finalizer(stdin, stdout, stderr, waiter)
    proc do
      [stdin, stdout, stderr].each(&:close)
      waiter.value unless Thread.current == waiter
    end
  end
end

20.times { Wrapper.new }
GC.start
puts "end"
