# ENV is shareable, but an instance variable of it belongs to the main
# ractor, as for a Ractor: another ractor that reads one raises.
ENV.instance_eval { @a = "hello" }
p ENV.instance_variable_get(:@a)
read = Ractor.new do
  ENV.instance_variable_get(:@a)
rescue Ractor::IsolationError => e
  e.class
end
p read.value
inside = Ractor.new do
  ENV.instance_eval { @a }
rescue Ractor::IsolationError => e
  e.class
end
p inside.value
p Ractor.new { ENV["HOME"].nil? }.value
