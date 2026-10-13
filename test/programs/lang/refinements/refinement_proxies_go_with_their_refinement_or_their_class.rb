# A refined module method found through a class that includes the module
# needs a node of its own for `super` (rb_vm_module_refinement_iclass).
# That node lives as long as both the refinement and the class do: it is
# made once while both are used, and it goes when either goes.
$stdout.sync = true
def iclasses = (GC.start; ObjectSpace.count_objects[:T_ICLASS])

module M
  def m = [:M]
end

# Many refinements of one class.
class C
  include M
end
start = iclasses
grew = []
30.times do
  o = C.new
  r = Module.new { refine(M) { def m = [:R, *super] } }
  blk = ->(x) { x.m }
  refined = blk.refined(r)
  first = refined.call(o)
  before = iclasses
  again = [refined.call(o), blk.refined(r).call(o)]
  grew << (iclasses > before)
  raise "wrong result" unless first == [:R, :M] && again == [[:R, :M], [:R, :M]]
end
p grew.any?, iclasses - start < 30

# Many classes, one refinement.
module R1
  refine(M) { def m = [:R1, *super] }
end
start = iclasses
grew = []
30.times do
  c = Class.new { include M }
  o = c.new
  refined = ->(x) { x.m }.refined(R1)
  refined.call(o)
  before = iclasses
  refined.call(o)
  grew << (iclasses > before)
end
p grew.any?, iclasses - start < 30
