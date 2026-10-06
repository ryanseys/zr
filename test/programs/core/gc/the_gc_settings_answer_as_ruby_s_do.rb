def t(name)
  p [name, yield]
rescue Exception => e
  p [name, :raise, e.class, e.message]
end
t(:auto_compact) { [(GC.auto_compact = true), GC.auto_compact] }
t(:auto_compact_int) { [(GC.auto_compact = 1), GC.auto_compact] }
GC.auto_compact = false
t(:verify_bad) { GC.verify_compaction_references(foo: 1) }
t(:config_full_mark) { GC.config[:rgengc_allow_full_mark] }
t(:config_bad) { GC.config(1) }
t(:stress_int) { [(GC.stress = 0x01), GC.stress] }
GC.stress = false
t(:raw_data) { GC::Profiler.enable; GC.start; GC::Profiler.raw_data.class }
GC::Profiler.disable
