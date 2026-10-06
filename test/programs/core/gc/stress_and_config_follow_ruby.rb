# GC.stress = true collects with a full mark each time.
GC.stress = true
Object.new
p GC.latest_gc_info(:major_by)
GC.stress = false
p GC.stress

# A stress number keeps what it was given.
GC.stress = 4
p GC.stress
GC.stress = false

# measure_total_time keeps a truth value; off, collections add no time.
p(GC.measure_total_time = 0)
p GC.measure_total_time
GC.measure_total_time = nil
p GC.measure_total_time
before = GC.stat(:time)
before_total = GC.total_time
5.times { GC.start }
p [GC.stat(:time) == before, GC.total_time == before_total]
GC.measure_total_time = true
p GC.measure_total_time

# GC.config: the implementation is read-only, keys are Symbols, and an
# unknown key is ignored.
p GC.config.keys
begin
  GC.config(implementation: "other")
rescue ArgumentError => e
  p e.message
end
begin
  GC.config("rgengc_allow_full_mark" => false)
rescue TypeError => e
  p e.message
end
begin
  GC.config(1)
rescue ArgumentError => e
  p e.message
end
p GC.config(unknown: 1)
p GC.config(rgengc_allow_full_mark: nil)
p GC.config(rgengc_allow_full_mark: true)
