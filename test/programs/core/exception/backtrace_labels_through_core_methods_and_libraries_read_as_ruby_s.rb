def t(l)
  r = yield
  puts "#{l}: #{r.inspect}"
rescue Exception => e
  puts "#{l}: !#{e.class}: #{e.message[0, 200]}"
end

t(:sl_core) { [[].method(:each).source_location, 1.method(:times).source_location, Kernel.instance_method(:then).source_location, [].method(:map).source_location, Kernel.instance_method(:tap).source_location, 1.method(:+).source_location] }
t(:bt_times) { 1.times { raise "x" } rescue $!.backtrace.first(3) }
t(:bt_each) { [1].each { raise "x" } rescue $!.backtrace.first(3) }
t(:bt_tap) { 1.tap { raise "x" } rescue $!.backtrace.first(3) }
t(:bt_loc) { 1.times { return caller_locations(0, 3).map { [_1.path, _1.lineno, _1.label, _1.base_label] } } }
t(:bt_kw) { Integer.sqrt(-1) rescue $!.backtrace.first(2) }
t(:bt_new) { Class.new { def initialize = raise("i") }.new rescue $!.backtrace.first(3) }
t(:bt_send) { send(:raise, "s") rescue $!.backtrace.first(2) }
t(:bt_method_missing) { Class.new { def method_missing(n) = super }.new.zz rescue $!.backtrace.first(3) }
t(:bt_define_method) { c = Class.new { define_method(:dm) { raise "d" } }; c.new.dm rescue $!.backtrace.first(2) }
t(:bt_block_labels) { proc { lambda { raise "q" }.call }.call rescue $!.backtrace.first(3) }
t(:bt_class_body) { class QQ; begin; raise "c"; rescue => e; e.backtrace.first; end; end }
t(:bt_singleton) { o = Object.new; def o.sm = raise("x"); o.sm rescue $!.backtrace.first }
t(:bt_module_function) { module MF; module_function; def mf = raise("x"); end; MF.mf rescue $!.backtrace.first }
t(:bt_refinement) { module RF; refine(Integer) { def rf = raise("x") }; end; using RF; 1.rf rescue $!.backtrace.first }
t(:bt_eval) { eval("raise 'e'") rescue $!.backtrace.first(2) }
t(:bt_instance_exec) { 1.instance_exec { raise "x" } rescue $!.backtrace.first(3) }
t(:bt_sort_by) { [2, 1].sort_by { raise "x" } rescue $!.backtrace.first(3) }
t(:bt_hash_each) { {a: 1}.each { raise "x" } rescue $!.backtrace.first(3) }
t(:bt_map_with_index) { [1].map.with_index { raise "x" } rescue $!.backtrace.first(4) }
t(:bt_enumerator_next) { e = Enumerator.new { |y| raise "x" }; e.next rescue $!.backtrace.first(4) }
t(:bt_fiber) { Fiber.new { raise "x" }.resume rescue $!.backtrace }
t(:bt_thread) { th = Thread.new { raise "x" }; th.report_on_exception = false; th.join rescue $!.backtrace }
t(:bt_struct) { Struct.new(:a, keyword_init: true).new(1) rescue $!.backtrace.first(2) }
t(:bt_dig) { [[1]].dig(0, 0, 0) rescue $!.backtrace.first(2) }
t(:bt_symproc) { [1].map(&:zz) rescue $!.backtrace.first(3) }
t(:bt_inject) { [1, 2].inject { raise "x" } rescue $!.backtrace.first(3) }
t(:bt_kernel_loop) { loop { raise "x" } rescue $!.backtrace.first(3) }
t(:bt_array_new) { Array.new(1) { raise "x" } rescue $!.backtrace.first(3) }
t(:bt_hash_new) { Hash.new { raise "x" }[1] rescue $!.backtrace.first(3) }
t(:bt_comparable) { c = Class.new { include Comparable; def <=>(o) = raise("x") }; c.new < c.new rescue $!.backtrace.first(3) }
t(:bt_to_s) { c = Class.new { def to_s = raise("x") }; "#{c.new}" rescue $!.backtrace.first(3) }
t(:bt_puts) { c = Class.new { def to_s = raise("x") }; puts c.new rescue $!.backtrace.first(4) }
t(:bt_format) { c = Class.new { def to_s = raise("x") }; format("%s", c.new) rescue $!.backtrace.first(3) }
t(:bt_json) { require "json"; c = Class.new { def to_json(*) = raise("x") }; JSON.generate([c.new]) rescue $!.backtrace.first(4) }
t(:bt_require) { File.write("bad.rb", "raise 'in lib'\n"); require "./bad" rescue $!.backtrace.first(4).map { _1.sub(Dir.pwd, ".") } }
t(:bt_marshal) { c = Class.new { def marshal_dump = raise("x") }; Object.const_set(:MD, c); Marshal.dump(MD.new) rescue $!.backtrace.first(3) }
t(:bt_set) { Set[1].each { raise "x" } rescue $!.backtrace.first(3) }
t(:bt_pp) { require "pp"; c = Class.new { def pretty_print(q) = raise("x") }; PP.pp(c.new, +"") rescue $!.backtrace.first(3) }
