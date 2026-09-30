# A finalizer runs once its object is collected, whether the program
# called GC.start or the allocator collected on its own: ruby runs it
# at the next safe point after the collection, so a program that waits
# for one sees it before it exits.

$collected = 0
def register = ObjectSpace.define_finalizer(Object.new, proc { |_id| $collected += 1 })
register
rounds = 0
while $collected == 0 && rounds < 2_000
  Array.new(10_000) { Object.new }
  rounds += 1
end
p $collected
p rounds < 2_000


