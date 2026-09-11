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
__END__
missing method: NoMethodError: undefined method 'foo' for an instance of #<Class:0xXX>
inspect: #<#<Class:0xXX>:0xXX>
to_s: #<#<Class:0xXX>:0xXX>
ivars: #<#<Class:0xXX>:0xXX @a=1>
frozen: FrozenError: can't modify frozen #<Class:0xXX>: #<#<Class:0xXX>:0xXX>
comparison: ArgumentError: comparison of Integer with #<Class:0xXX> failed
class: #<Class:0xXX>
subclass: #<#<Class:0xXX>:0xXX>
error class: #<Class:0xXX>: #<Class:0xXX>
error to_s: #<Class:0xXX>
anonymous module: NoMethodError: undefined method 'foo' for module #<Module:0xXX>
