# Thread::Backtrace::Location has no allocator and no `new`: only the
# core makes one, so clone, dup, allocate and new all fail, as in ruby.
loc = caller_locations(0, 1).first
klass = Thread::Backtrace::Location

[
  ["clone", -> { loc.clone }],
  ["clone(freeze: false)", -> { loc.clone(freeze: false) }],
  ["dup", -> { loc.dup }],
  ["allocate", -> { klass.allocate }],
  ["new", -> { klass.new }],
  ["new(row)", -> { klass.new("a.rb:1:in 'm'") }]
].each do |label, f|
  r = f.call
  puts "#{label}: #{r.class}"
rescue Exception => e
  puts "#{label}: #{e.class}: #{e.message}"
end

p klass.respond_to?(:new)
p klass.respond_to?(:made)

# The core's own readers still make them.
p loc.class
p caller_locations(0).first.lineno
p Thread.current.backtrace_locations(0, 1).first.class
begin
  raise "x"
rescue => e
  p e.backtrace_locations.first.class
  p e.backtrace_locations.first.lineno
end
def m = caller_locations(1, 1).first.label
p m
