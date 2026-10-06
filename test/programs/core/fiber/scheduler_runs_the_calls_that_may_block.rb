# A non-blocking fiber hands open(2), close(2) of a stream that writes,
# stat(2), access(2) and unlink(2) to its scheduler's
# blocking_operation_wait, as an object of an unnamed class whose #call
# runs the operation once. IO reads and writes go to io_read and
# io_write, and a hook's negative errno raises.
require_relative "fiber_scheduler/scheduler"
require "tmpdir"
ops = []
Thread.new do
  sched = Class.new(Scheduler) do
    define_method(:blocking_operation_wait) do |op|
      ops << [op.class.name, op.class.superclass, op.respond_to?(:call)]
      Thread.new { op.call }.join
      ops << (op.call rescue $!.message)
    end
  end.new
  Fiber.set_scheduler(sched)
  Fiber.schedule do
    ops << :started
    File.open(__FILE__) { |f| ops << f.gets }
    path = File.join(Dir.tmpdir, "zr_blocking_#{$$}")
    File.write(path, "x")
    ops << File.exist?(path) << File.size(path)
    File.delete(path)
    ops << :done
  end
  ops << :scheduled
end.join
ops.each { |o| p o }
failures = []
Thread.new do
  Fiber.set_scheduler(IOErrorScheduler.new)
  r, w = IO.pipe
  Fiber.schedule do
    failures << (r.read(1) rescue $!.class)
    failures << (w.write("x") rescue $!.class)
  end
end.join
p failures
Thread.new do
  Fiber.set_scheduler(IOScheduler.new)
  r, w = IO.pipe
  Fiber.schedule { w.write("abc"); w.syswrite("de"); w.close }
  Fiber.schedule { p r.read }
end.join


