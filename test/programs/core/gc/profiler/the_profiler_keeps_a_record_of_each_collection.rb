p GC::Profiler.raw_data
p GC::Profiler.result
GC::Profiler.enable
p GC::Profiler.raw_data
GC.start
GC.start
rows = GC::Profiler.raw_data
p rows.size
p rows[0].keys
p rows[0].transform_values(&:class)
p rows[0][:GC_FLAGS][:gc_by]
p rows.all? { |row| row[:HEAP_USE_SIZE] <= row[:HEAP_TOTAL_SIZE] && row[:GC_TIME] >= 0 }
p rows[0][:GC_INVOKE_TIME] <= rows[1][:GC_INVOKE_TIME]
p GC::Profiler.total_time == rows.sum { |row| row[:GC_TIME] }
result = GC::Profiler.result.lines
p result.size
p result[0] == "GC #{GC.count} invokes.\n"
puts result[1]
p result[2].start_with?("    1 ")

GC::Profiler.disable
p GC::Profiler.raw_data
GC.start
GC::Profiler.enable
p GC::Profiler.raw_data.size
GC::Profiler.clear
p GC::Profiler.raw_data, GC::Profiler.result, GC::Profiler.total_time
GC::Profiler.disable

info = GC.compact
p info.keys
p info[:considered][:T_STRING].positive?
p GC.latest_compact_info.equal?(info) || GC.latest_compact_info == info

