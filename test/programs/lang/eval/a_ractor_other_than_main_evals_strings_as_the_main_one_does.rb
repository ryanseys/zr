# eval, Binding#eval, instance_eval and class_eval with a String work in
# a Ractor other than main, as ERB#result does; the compile runs on the
# main Ractor and the code runs in the one that asked.
require "erb"
Warning[:experimental] = false

p Ractor.new { ERB.new("Hello, <%= 'world' %>!").result(binding) }.value
src = "<% [1, 2].each do |i| %>\n<%= i %>\n<% end %>\n"
p Ractor.new(src) { |s| ERB.new(s, trim_mode: "-").result(binding) }.value
p Ractor.new(src) { |s| ERB.new(s, trim_mode: "<>").result(binding) }.value
erb = ERB.new("<%= 1 + 1 %>").freeze
p 2.times.map { Ractor.new(erb) { |e| e.result(binding) } }.map(&:value)

p(Ractor.new do
  x = 20
  [eval("x + 1"), binding.eval("x * 2"), "abc".instance_eval("size"),
   Class.new.class_eval("def hi = :hi; self").new.hi, Ractor.current == Ractor.main]
end.value)

p(Ractor.new do
  eval("1 +")
rescue SyntaxError => e
  [e.class, e.message.lines.first.chomp]
end.value)

p(Ractor.new do
  eval("raise ArgumentError, 'from the string'")
rescue => e
  [e.class, e.message, e.backtrace_locations.first.label]
end.value)
p eval("40 + 2")
