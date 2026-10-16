# A block given to class_eval, module_eval or instance_eval shows the
# frame of the method it was given to, and no class_exec or
# instance_exec under it. This program evals a string, so the eval forms
# of these methods are the ones that run.
eval("1 + 1")

class Box; end

def where = caller_locations(1, 2).map { |l| "#{l.lineno}:#{l.label}" }

def report(name)
  yield
rescue => e
  puts "#{name}: #{e.backtrace[0, 3].join(" | ")}"
end

p Box.class_eval { where }
p Box.module_eval { where }
p Box.class_exec { where }
p Box.module_exec { where }
p Box.new.instance_eval { where }
p Box.new.instance_exec { where }
p 1.instance_eval { where }

report("class_eval") { Box.class_eval { raise "boom" } }
report("module_eval") { Box.module_eval { raise "boom" } }
report("instance_eval") { Box.new.instance_eval { raise "boom" } }
report("instance_exec") { Box.new.instance_exec(1) { |x| raise "boom #{x}" } }
p Box.class_eval { self }
p(Box.new.instance_eval { self.class })
p(Box.class_eval { def made = :made; instance_method(:made).owner })
o = Object.new
o.instance_eval { def only = :only }
p o.singleton_methods

t = Thread.new { Box.class_eval { raise "in a thread" } }
t.report_on_exception = false
begin
  t.join
rescue => e
  puts "thread: #{e.backtrace[0, 2].join(" | ")}"
end
Box.class_eval { raise "uncaught" }
