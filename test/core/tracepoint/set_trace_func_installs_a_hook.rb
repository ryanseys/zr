# `set_trace_func` is a real row: `defined?`, `private_method_defined?`
# and clearing with nil answer as ruby does, and a Proc it takes is
# called with each event as `(event, file, line, id, binding, klass)`.

def show(label)
  puts "#{label}: #{yield.inspect}"
rescue Exception => e # rubocop:disable Lint/RescueException
  puts "#{label}: #{e.class}: #{e.message}"
end

show("defined?") { defined?(set_trace_func) }
show("private_method_defined?") { Kernel.private_method_defined?(:set_trace_func) }
show("clearing with nil") { set_trace_func(nil) }

events = []
show("installing a Proc") do
  set_trace_func(proc { |ev, _file, _line, id, _binding, _klass| events << [ev, id] })
  :installed
end
def traced = 1
traced
set_trace_func(nil) rescue nil
show("the hook fired") { events.any? { |ev, id| ev == "call" && id == :traced } }

__END__
defined?: "method"
private_method_defined?: true
clearing with nil: nil
installing a Proc: :installed
the hook fired: true
