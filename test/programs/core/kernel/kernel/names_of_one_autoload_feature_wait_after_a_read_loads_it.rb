# ruby keeps one autoload record for each feature, and every name that
# autoloads that feature shares it. After a read of one name loads the
# file, the other names still wait for it, even though $LOADED_FEATURES
# has the file. A plain require of the file makes them declared only.
def state(name) = [Object.autoload?(name) ? :waits : nil, Object.const_defined?(name)]

shared = File.expand_path("one_feature/shared", __dir__)
Object.autoload :Shared1, shared
Object.autoload :Shared2, shared
p [:before, state(:Shared2)]
Shared1
p [:after_a_read, state(:Shared2), Object.constants.include?(:Shared2)]
Object.autoload :Shared3, shared
p [:declared_after, state(:Shared3)]
begin
  Shared2
rescue NameError => e
  p [e.class, e.message]
end
p [:after_its_own_read, state(:Shared2), Object.constants.include?(:Shared2)]
$LOADED_FEATURES.delete("#{shared}.rb")
p [:file_deleted, state(:Shared3)]

required = File.expand_path("one_feature/required", __dir__)
Object.autoload :Required2, required
require required
p [:after_require, state(:Required2)]
Object.autoload :Required3, required
p [:declared_after_require, state(:Required3)]

# Each name reads the file again once it leaves $LOADED_FEATURES, and the
# other threads wait for that read: each read runs the file once.
class Counter
  def initialize = (@value = 0; @lock = Mutex.new)
  def increment = @lock.synchronize { (@value += 1) - 1 }
  def get = @lock.synchronize { @value }
end

class Barrier
  def initialize(count) = (@count = count; @state = 0; @lock = Mutex.new; @cond = ConditionVariable.new)

  def await
    @lock.synchronize do
      @state += 1
      if @state >= @count
        @state = 0
        @cond.broadcast
        true
      else
        @cond.wait(@lock)
        false
      end
    end
  end
end

counted = File.expand_path("one_feature/counted", __dir__)
names = Array.new(10) { |i| :"Counted#{i}" }
names.each { |name| Object.autoload name, counted }
$counter = Counter.new
barrier = Barrier.new(6)
threads = Array.new(6) do
  Thread.new do
    names.map do |name|
      last = barrier.await
      $LOADED_FEATURES.delete("#{counted}.rb") if last
      barrier.await
      Object.const_get(name).foo
    end
  end
end
p threads.map(&:value).uniq
p $counter.get
