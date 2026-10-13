# A raise calls the exception's own `exception` and `set_backtrace`, as
# setup_exception does: set_backtrace gets the frames as Strings, or
# raise's third argument as it is, and the error keeps its locations when
# the method stores the frames with super. Thread#raise calls both in the
# caller, and the target thread calls `exception` again with no
# arguments, and set_backtrace only when it captures the frames itself.
$stdout.sync = true
class Logged < Exception
  attr_accessor :log

  def initialize(*)
    @log = []
    super
  end

  def exception(*args)
    @log << [:exception, Thread.current == Thread.main ? :main : :thread, args]
    super
  end

  def set_backtrace(bt)
    @log << [:set_backtrace, Thread.current == Thread.main ? :main : :thread, bt.is_a?(Array) && bt.first.to_s.include?(":in ") ? :frames : bt]
    super
  end
end

class Keeping < Exception
  def set_backtrace(bt) = super(bt.map(&:upcase))
end

class Ignoring < Exception
  def set_backtrace(_bt) = nil
end

def show(label)
  yield
rescue Exception => e
  p [label, e.class, e.message, e.log, e.backtrace&.size, e.backtrace_locations&.size]
end

e = Logged.new
show(:plain) { raise e }
show(:message) { raise Logged.new, "m" }
show(:given) { raise Logged.new, "m", ["a.rb:1"] }
show(:locations) { raise Logged.new, "m", caller_locations(0) }
show(:class) { raise Logged }
show(:again) { raise e }

def raise_kept
  raise Keeping, "k"
rescue Keeping => e
  [e.backtrace.first.end_with?("'OBJECT#RAISE_KEPT'"), e.backtrace_locations.nil?]
end
p raise_kept

def raise_ignored
  raise Ignoring, "i"
rescue Ignoring => e
  [e.backtrace&.first&.end_with?("'Object#raise_ignored'"), e.backtrace_locations&.first&.label]
end
p raise_ignored

[["msg"], [], ["msg", ["a.rb:1"]]].each do |extra|
  got = nil
  t = Thread.new do
    sleep
  rescue Exception => err
    got = err
  end
  Thread.pass until t.status == "sleep"
  exc = Logged.new
  t.raise(exc, *extra)
  t.join
  p [extra, got.equal?(exc), got.message == (extra.first || "Logged"), exc.log]
end
