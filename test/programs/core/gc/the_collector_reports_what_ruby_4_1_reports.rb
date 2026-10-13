# ruby 4.1's GC surface: stat takes a scope and has new keys, start takes
# global:, stat_heap gains heap_allocatable_slots, latest_gc_info drops
# retained_weak_references_count and says :sweeping after a lazy sweep,
# and GC::Profiler numbers its records, keeps a bounded ring of them and
# takes limit:, since: and max_records:.
def show
  p yield
rescue => e
  p [e.class, e.message]
end

show { GC.method(:start).parameters }
show { GC.method(:stat).parameters }
show { GC.stat(scope: :global).keys }
show { GC.stat(scope: :local).keys == GC.stat.keys }
show { GC.stat(scope: :ractor).keys == GC.stat.keys }
show { GC.stat(scope: :all) }
show { GC.stat(:count, scope: :global).is_a?(Integer) }
show { GC.stat(:heap_live_slots, scope: :global) }
show { %i[total_malloc_bytes total_free_bytes heap_allocatable_bytes global_gc_count page_pool_arenas page_pool_arenas_freed page_pool_total_pages page_pool_discarded_pages].map { |k| GC.stat(k).is_a?(Integer) } }
show { GC.stat.key?(:heap_allocatable_slots) }
show { GC.stat(:total_malloc_bytes) >= GC.stat(:total_free_bytes) }
show { a = GC.stat(:total_malloc_bytes); x = "z" * 100_000; GC.stat(:total_malloc_bytes) > a }
show { GC.stat_heap(0).keys }
show { GC.latest_gc_info.keys }
show { GC.latest_gc_info(:retained_weak_references_count) }

show { GC.start(global: false); GC.latest_gc_info.values_at(:gc_by, :immediate_sweep, :state) }
show { GC.start(immediate_sweep: false); GC.latest_gc_info.values_at(:immediate_sweep, :state) }
show { ObjectSpace.garbage_collect(global: true); GC.latest_gc_info(:state) }
show do
  count = GC.count
  junk = nil
  junk = Object.new while GC.count == count
  GC.latest_gc_info.values_at(:gc_by, :immediate_sweep, :state)
end

show { GC::Profiler.method(:raw_data).arity }
show { GC::Profiler.configure }
show { GC::Profiler.configure(max_records: 0) }
show { GC::Profiler.configure(max_records: -1) }
show { GC::Profiler.configure(max_records: "2") }
show { GC::Profiler.raw_data(limit: -1) }
show { GC::Profiler.raw_data(since: -1) }
show { GC::Profiler.raw_data(nope: 1) }
show { GC::Profiler.raw_data(1) }

GC::Profiler.enable
GC::Profiler.configure(max_records: 3)
5.times { GC.start }
rows = GC::Profiler.raw_data
show { rows.size }
seqs = rows.map { |row| row[:GC_SEQUENCE] }
show { seqs.each_cons(2).all? { |a, b| b == a + 1 } }
show { GC::Profiler.raw_data(limit: 2).map { |row| row[:GC_SEQUENCE] } == seqs.last(2) }
show { GC::Profiler.raw_data(since: seqs[0]).map { |row| row[:GC_SEQUENCE] } == seqs.drop(1) }
show { GC::Profiler.raw_data(since: seqs.last) }
show { GC::Profiler.raw_data(limit: 0) }
show { rows.last[:GC_FLAGS].keys }
show { rows.all? { |row| row[:GC_WALL_TIME] >= 0 && row[:GC_MARK_WALL_TIME] + row[:GC_SWEEP_WALL_TIME] <= row[:GC_WALL_TIME] + 0.001 } }
GC::Profiler.clear
GC.start
show { GC::Profiler.raw_data.map { |row| row[:GC_SEQUENCE] } == [seqs.last + 1] }
GC::Profiler.configure(max_records: nil)
6.times { GC.start }
show { GC::Profiler.raw_data.size }
GC::Profiler.disable
show { GC::Profiler.raw_data }
