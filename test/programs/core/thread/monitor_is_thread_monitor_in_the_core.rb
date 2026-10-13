# ruby 4.1 moves Monitor into the core as Thread::Monitor, with its
# ConditionVariable inside it; monitor.rb keeps MonitorMixin and the
# mon_* aliases, and MonitorMixin::ConditionVariable is the same class.
p Monitor, Monitor.equal?(Thread::Monitor), Monitor.name
p Thread::Monitor::ConditionVariable, MonitorMixin::ConditionVariable.equal?(Thread::Monitor::ConditionVariable)
p Monitor.ancestors.take(2), Monitor.superclass
p $LOADED_FEATURES.include?("monitor.so")
p %i[enter exit try_enter synchronize mon_locked? mon_owned? mon_check_owner new_cond wait_for_cond].map { |m| Monitor.instance_method(m).owner }
p %i[mon_enter mon_exit mon_try_enter try_mon_enter mon_synchronize].map { |m| [m, Monitor.instance_method(m).original_name] }

m = Monitor.new
p m.instance_variables
cond = m.new_cond
p cond.class, cond.instance_variables
m.synchronize { m.synchronize { p [m.mon_locked?, m.mon_owned?] } }
p [m.mon_locked?, m.mon_owned?]
p m.try_enter, m.mon_try_enter
m.exit
m.mon_exit
p m.mon_locked?
begin
  m.exit
rescue ThreadError => e
  p e.message
end

class Box
  include MonitorMixin
end
b = Box.new
p b.new_cond.class, b.synchronize { :inside }
p MonitorMixin.instance_method(:synchronize).original_name
