# A collection is minor or major, so the two counts add up to the
# one the collector answers, and the trace and the sweep are timed
# apart inside the total.
GC.start
first = GC.stat
p first[:count] == first[:minor_gc_count] + first[:major_gc_count]
p first[:major_gc_count] >= 1
p first[:marking_time] + first[:sweeping_time] <= first[:time]

kept = []
i = 0
while i < 200_000
  kept << Object.new
  kept.clear if kept.size > 1000
  i += 1
end
GC.start
later = GC.stat
p later[:count] == later[:minor_gc_count] + later[:major_gc_count]
p later[:count] > first[:count]
p later[:major_gc_count] > first[:major_gc_count]
p later[:marking_time] >= first[:marking_time]
p later[:sweeping_time] >= first[:sweeping_time]
p later[:marking_time] + later[:sweeping_time] <= later[:time]

# Each key answers on its own as well, and each is an Integer. The
# count only ever goes up, and a collection may have run since the
# Hash above was filled -- under `GC.stress` one runs at every
# allocation, here and on ruby alike.
p GC.stat(:major_gc_count) >= later[:major_gc_count]
p [later[:minor_gc_count], later[:major_gc_count], later[:marking_time], later[:sweeping_time]].map(&:class)
p GC.stat(:minor_gc_count) >= 0
