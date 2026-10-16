def t(l)
  r = yield
  puts "#{l}: #{r.inspect}"
rescue Exception => e
  puts "#{l}: !#{e.class}: #{e.message[0, 200]}"
end
t(:pack_R) { [1, 300, 2**70].pack("R*").bytes }
t(:pack_r) { [-1, -300, 63, -64].pack("r*").bytes }
t(:unpack_R) { "\xAC\x02\x01".b.unpack("R*") }
t(:unpack_caret) { "\xAC\x02\x01".b.unpack("R^R^") }
t(:pack_xbang) { [1, 2].pack("Cx!4N").bytes }
t(:pack_atbang) { [1, 2].pack("C@!QQ").bytes }
t(:unpack_xbang) { "\x01\x00\x00\x00\x00\x00\x00\x02".b.unpack("Cx!4N") }
t(:env_fetch_values) { ENV["A1"] = "x"; ENV.fetch_values("A1") }
t(:env_fetch_values_miss) { ENV.fetch_values("A1", "NOPE_ZZ") }
t(:env_fetch_values_blk) { ENV.fetch_values("A1", "NOPE_ZZ") { |k| k.downcase } }
t(:bit_count) { [0, 1, 255, 2**100 - 1].map(&:bit_count) }
t(:bit_count_neg) { -1.bit_count }
t(:integer_at) { /(\d+)-(?<x>\d+)/.match("12-34").then { |m| [m.integer_at(1), m.integer_at(:x), m.integer_at(0)] } }
t(:integer_at_base) { /(\w+)/.match("ff").integer_at(1, 16) }
class A; end; class B < A; end; module M; end; class C2 < B; include M; end
t(:descendants) { A.descendants.map(&:name).sort }
t(:descendants_m) { M.descendants.map(&:name) }
class P; private def priv = 1; end
t(:method_defined3) { [P.method_defined?(:priv), P.method_defined?(:priv, true, true)] }
t(:id2ref) { ObjectSpace._id2ref(1) }
t(:range_clamp) { (1..10).clamp(3, 5) }
t(:range_clamp2) { (1..10).clamp(5..20) }
t(:regexp_frozen) { [Regexp.new("a").frozen?, /a/.frozen?, Class.new(Regexp).new("a").frozen?] }
t(:to_set_args) { [1].to_set(Set) }
t(:bit_get) { "\x05".b.bit_get(0) }
t(:bit_ops) { s = "\x0f".b; [s.bit_set?(0), s.bit_count, s.bitwise_not, "\x0f".b.bitwise_and("\x3c".b), "\x0f".b.bitwise_xor("\xff".b)] }
t(:bit_set) { s = +"\x00"; s.bit_set(3); s.bit_flip(0); s.bit_clear(3); s }
t(:tr_hash) { "hello".tr({"l" => "L", "o" => "0"}) }
t(:tr_hash_multi) { "hello".tr({"ll" => "y", "h" => "J"}) }
t(:sym_to_s_frozen) { :abc.to_s.frozen? }
t(:tvar_nil) { th = Thread.current; th.thread_variable_set(:a, 1); th.thread_variable_set(:a, nil); th.thread_variables }
t(:source_range) { caller_locations(0, 1)[0].source_range }
t(:autoload_relative) { Object.respond_to?(:autoload_relative, true) }
t(:ruby_prism) { defined?(Ruby::Prism) }
t(:ruby_prism_parse) { Ruby::Prism.parse("1 + 2").value.class }
t(:proc_refined) { module R1; refine(Integer) { def dbl = self * 2 }; end; pr = proc { 3.dbl }; pr.refined(R1).call }
t(:struct_index) { Struct.new(:a).new(1)[2**40] }
t(:urandom_big) { Random.urandom(2**63) }
t(:ractor_value_twice) { r = Ractor.new { 1 }; [r.value, (r.value rescue $!.class)] }
t(:make_shareable_io) { Ractor.make_shareable($stdout) }
t(:shareable_io) { Ractor.shareable?(STDIN.dup.freeze) }
t(:r2k_hash) { Hash.ruby2_keywords_hash?({}) }
