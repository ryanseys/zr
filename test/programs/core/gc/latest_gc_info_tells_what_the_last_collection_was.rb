# The keys, in CRuby's order.
p GC.latest_gc_info.keys

# A full GC.start is major because the program asked.
3.times { GC.start }
info = GC.latest_gc_info
p info.values_at(:major_by, :gc_by, :immediate_sweep, :state, :have_finalizer)
p info.key?(:need_major_by)

# After full collections, a minor one has no major reason.
GC.start(full_mark: false)
p GC.latest_gc_info(:major_by)
p GC.latest_gc_info(:gc_by)
GC.start(full_mark: true)
p GC.latest_gc_info(:major_by)

# The sweep flag shows what GC.start was given.
GC.start(immediate_sweep: false)
p GC.latest_gc_info(:immediate_sweep)
GC.start(immediate_sweep: true)
p GC.latest_gc_info(:immediate_sweep)
ObjectSpace.garbage_collect(full_mark: false)
p GC.latest_gc_info(:major_by)
p ObjectSpace.garbage_collect

# Minor collections go on until the next must be major; then a minor
# request is upgraded, and the major has a reason.
3.times { GC.start }
p GC.latest_gc_info(:need_major_by)
objects = []
rounds = 0
while GC.latest_gc_info(:need_major_by).nil? && rounds < 10_000
  objects << 100.times.map { +"*" }
  GC.start(full_mark: false)
  rounds += 1
end
need = GC.latest_gc_info(:need_major_by)
GC.start(full_mark: false)
p(need.nil? || !GC.latest_gc_info(:major_by).nil?)

# A collection that an allocation starts.
GC.start
count = GC.count
garbage = nil
garbage = Object.new while GC.count == count
p GC.latest_gc_info(:gc_by)

# A Hash argument is filled and returned; a key returns its value.
h = {}
p GC.latest_gc_info(h).equal?(h)
p h.keys == GC.latest_gc_info.keys
p GC.latest_gc_info(:state)
begin
  GC.latest_gc_info(:invalid)
rescue ArgumentError => e
  p e.message
end
begin
  GC.latest_gc_info(:"\u{30eb 30d3 30fc}")
rescue ArgumentError => e
  p [e.message, e.message.encoding]
end
begin
  GC.latest_gc_info("major_by")
rescue TypeError => e
  p e.message
end

# The weak references: a WeakMap's keys and values count, and they stop
# counting once their objects die.
GC.start
before = GC.latest_gc_info(:weak_references_count)
before_kept = GC.latest_gc_info(:retained_weak_references_count)
wmap = ObjectSpace::WeakMap.new
keep = Array.new(1000) { Object.new.tap { |o| wmap[o] = nil } }
GC.start
p GC.latest_gc_info(:weak_references_count) >= before + 1000 - 100
p GC.latest_gc_info(:retained_weak_references_count) >= before_kept + 1000 - 100
p GC.latest_gc_info(:retained_weak_references_count) <= GC.latest_gc_info(:weak_references_count)
full = GC.latest_gc_info(:weak_references_count)
keep.clear
keep = nil
GC.start
GC.start
p GC.latest_gc_info(:weak_references_count) <= full - 1000 + 100
p GC.latest_gc_info(:retained_weak_references_count) <= GC.latest_gc_info(:weak_references_count)
