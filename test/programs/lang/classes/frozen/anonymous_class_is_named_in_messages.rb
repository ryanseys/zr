# A class with no name shows as #<Class:0x...> wherever a message names
# it: a missing method, inspect, a frozen object, a failed comparison.
def show(label)
  answer = begin
    yield
  rescue => e
    "#{e.class}: #{e.message}"
  end
  puts "#{label}: #{answer.to_s.gsub(/0x\h+/, "0xXX")}"
end

anon = Class.new
show("missing method") { anon.new.foo }
show("inspect") { anon.new.inspect }
show("to_s") { anon.new.to_s }
show("ivars") { anon.new.tap { _1.instance_variable_set(:@a, 1) }.inspect }
show("frozen") { anon.new.freeze.instance_variable_set(:@a, 1) }
show("comparison") { 1 < anon.new }
show("class") { anon.inspect }
show("subclass") { Class.new(anon).new.inspect }
show("error class") { raise Class.new(StandardError) }
show("error to_s") { Class.new(StandardError).new.to_s }
show("anonymous module") { Module.new.foo }
