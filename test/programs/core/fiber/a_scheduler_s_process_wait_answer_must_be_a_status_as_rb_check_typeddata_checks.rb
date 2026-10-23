# A fiber scheduler's process_wait answers a blocking wait as it gives
# its answer: Process::Status.wait returns it, Process.wait reads nil as
# no child, and anything else that is no Process::Status is a TypeError.
Warning[:experimental] = false
require "fiber"
class Sched
  def initialize(answer) = @answer = answer
  def process_wait(pid, flags)
    Fiber.blocking { Process.wait(pid, flags) }
    @answer
  end
  def block(*) = nil
  def unblock(*) = nil
  def kernel_sleep(*) = nil
  def io_wait(*) = nil
  def fiber(&b) = Fiber.new(blocking: false, &b).tap(&:resume)
  def close = nil
  def fiber_interrupt(*) = nil
end
[false, nil, "str", 3, :sym].each do |answer|
  Thread.new do
    Fiber.set_scheduler Sched.new(answer)
    Fiber.schedule do
      begin
        p [answer, :system, system("true")]
      rescue => e
        p [answer, :system, e.class, e.message]
      end
      begin
        pid = spawn("true")
        p [answer, :wait, Process.wait(pid)]
      rescue => e
        p [answer, :wait, e.class, e.message]
      end
      p [answer, :status_wait, Process::Status.wait(spawn("true"))]
      begin
        pid = spawn("true")
        p [answer, :wait2, Process.wait2(pid)]
      rescue => e
        p [answer, :wait2, e.class, e.message]
      end
    end
  end.join
end
Thread.new do
  scheduler = Sched.new(nil)
  def scheduler.process_wait(pid, flags) = Fiber.blocking { Process::Status.wait(pid, flags) }
  Fiber.set_scheduler scheduler
  Fiber.schedule do
    p [system("true"), $?.success?, system("false"), $?.exitstatus]
    pid = spawn("exit 3")
    p [Process.wait(pid) == pid, $?.exitstatus]
    p Process::Status.wait(spawn("true")).success?
    # A child that cannot have exited yet, however late the wait comes.
    pid = spawn("sleep 30")
    p Process.wait(pid, Process::WNOHANG)
    Process.kill(:KILL, pid)
    Process.wait(pid)
  end
end.join
