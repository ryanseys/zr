# Process.warmup runs CRuby's GC steps: it promotes every live object
# to the old generation, compacts the heap, frees the empty pages and
# computes each string's coderange. zr's collector has no object ages,
# no compaction and no coderange cache, so warmup is one full GC.
require "objspace"

obj = Object.new
p ObjectSpace.dump(obj).include?('"old":true')
str = "a" * 12
str.force_encoding(Encoding::UTF_16LE)
str.force_encoding(Encoding::BINARY)
p ObjectSpace.dump(str)[/"coderange":"\w+"/]
GC.start
majors = GC.stat(:major_gc_count)
compactions = GC.stat(:compact_count)
Process.warmup
p ObjectSpace.dump(obj).include?('"old":true')
p ObjectSpace.dump(str)[/"coderange":"\w+"/]
p GC.stat(:major_gc_count) - majors
p GC.stat(:compact_count) - compactions
p GC.stat(:total_freed_pages).positive?
