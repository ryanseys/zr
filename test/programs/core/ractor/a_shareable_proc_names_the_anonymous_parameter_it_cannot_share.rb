# A shareable Proc made inside a method with an anonymous rest reads
# that rest through `super`, so ruby names it as `*` when its value is
# not shareable. Named locals keep their own names.
name = "\u{2603 26a1}"
begin
  eval("#{name} = nil; Ractor.shareable_proc{#{name} = nil}")
rescue Ractor::IsolationError => e
  puts e.message
end
begin
  eval("#{name} = []; Ractor.shareable_proc{#{name}}")
rescue Ractor::IsolationError => e
  puts e.message
end
obj = Object.new
def obj.foo(*) = Ractor.shareable_proc { super }
begin
  obj.foo(*[])
rescue Ractor::IsolationError => e
  puts e.message
end
