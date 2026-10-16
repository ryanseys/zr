def t(l)
  r = yield
  puts "#{l}: #{r.inspect}"
rescue Exception => e
  puts "#{l}: !#{e.class}: #{e.message[0, 200]}"
end
module Mod; def self.x = 1; end
t(:alias_fallback) { Module.new { alias_method :zz, :puts } ; :ok }
t(:alias_prepend) { pm = Module.new { def foo = 1 }; c = Class.new { def foo = 2 }; c.prepend(pm); c.class_eval { alias bar foo }; c.new.bar }
# The clone's constant warning names the clone by its address.
t(:mod_clone_const) { verbose, $VERBOSE = $VERBOSE, nil; m = Module.new; m.const_set(:K, 1); m.module_eval "def k = K"; m2 = m.clone; m2.const_set(:K, 2) rescue nil; k = Object.new.extend(m2).k; $VERBOSE = verbose; k }
t(:pattern_deconstruct) { case {a: 1, b: [2, 3]}; in {a: Integer => x, b: [_, y]} then [x, y] end }
t(:pattern_find) { case [1, 2, 3, 42, 5]; in [*, 40.. => n, *post] then [n, post] end }
t(:pattern_nomatch) { case 1; in String then 1 end }
t(:pattern_keyerr) { {a: 1} => {b:} }
t(:pin_expr) { x = 2; case 4; in ^(x * 2) then :y end }
t(:it_param) { [1, 2].map { it * 2 } }
t(:numbered) { [[1, 2]].map { _1 + _2 } }
t(:anon_fwd) { def f1(*, **, &) = f2(*, **, &); def f2(*a, **k, &b) = [a, k, b&.call]; f1(1, z: 2) { 3 } }
t(:dots) { def g1(...) = g2(...); def g2(*a, **k) = [a, k]; g1(1, 2, k: 3) }
t(:endless) { def sq(x) = x * x; sq(5) }
t(:hash_shorthand) { x = 1; y = 2; {x:, y:} }
t(:rescue_mod) { (raise "a" rescue "b") }
t(:retry) { n = 0; begin; n += 1; raise "x" if n < 3; n; rescue; retry; end }
t(:throw) { catch(:a) { throw :a, 5 } }
t(:throw_uncaught) { throw :nope }
t(:flipflop) { (1..10).select { |i| (i == 3)..(i == 5) } }
t(:begin_end_while) { i = 0; begin i += 1 end while i < 0; i }
t(:defined) { [defined?(@@x), defined?(super), defined?(yield), defined?(String), defined?(zzz), defined?(puts), defined?(3 + 3), defined?($~)] }
t(:block_local) { x = 1; [1].each { |y; x| x = 9 }; x }
t(:masgn) { a, (b, *c), d = 1, [2, 3, 4], 5; [a, b, c, d] }
t(:op_asgn) { h = Hash.new(0); h[:a] += 1; h[:b] ||= 2; h[:c] &&= 3; h }
t(:safe_nav) { nil&.foo&.bar }
t(:str_frozen_lit) { "abc".frozen? }
t(:chilled) { s = "abc"; s << "d"; s }
t(:symbol_proc_refine) { %w[a b].map(&:upcase) }
t(:obj_inspect) { o = Object.new; o.instance_variable_set(:@a, 1); o.inspect.sub(/0x\h+/, "X") }
t(:data) { D = Data.define(:a, :b); d = D.new(a: 1, b: 2); [d, d.with(b: 3), D.new(1, 2).to_h, (D.new(1) rescue $!.message)] }
t(:struct_kw) { S = Struct.new(:a, :b); [S.new(1, 2), S.new(a: 1, b: 2), S.new(1).to_a] }
t(:set_inspect) { [Set[1, 2], Set[], Set[Set[1]]].map(&:inspect) }
t(:hash_inspect) { {1 => 2, a: 3, "b" => :c, nil => nil, :"a b" => 1, a?: 1, B: 2, "+": 3}.inspect }
t(:refinement) { module RR; refine(String) { def shout = upcase + "!" }; end; using RR; "a".shout }
t(:ractor_basic) { Ractor.new(3) { |x| x * 2 }.value }
t(:ractor_port) { port = Ractor::Port.new; Ractor.new(port) { |p| p << 42 }; port.receive }
t(:warning_cat) { Warning[:deprecated] }
t(:const_missing) { Object.const_get(:NoSuchThingZZ) }
t(:method_missing_msg) { 5.nosuch }
t(:nomethod_private) { Object.new.puts }
t(:frozen_err) { "a".freeze << "b" }
t(:frozen_err_hash) { {}.freeze[1] = 2 }
t(:zerodiv) { 1 / 0 }
t(:argerr) { def ar(a, b = 1, *c, d:, e: 2, **f) = 1; ar }
t(:argerr_kw) { def ak(a:) = 1; ak(b: 1) }
t(:params) { def pm(a, b = 1, *c, d, e:, f: 2, **g, &h) = 1; method(:pm).parameters }
t(:arity) { [proc { |a, b| }.arity, lambda { |*a, b| }.arity, method(:puts).arity, proc { |(a, b)| }.parameters] }
t(:curry) { ->(a, b, c) { a + b + c }.curry[1][2][3] }
t(:compose) { (->(x) { x + 1 } >> ->(x) { x * 2 }).call(3) }
t(:obj_respond_missing) { c = Class.new { def respond_to_missing?(n, p = false) = n == :zz; def method_missing(n, *) = n == :zz ? 1 : super }; o = c.new; [o.respond_to?(:zz), o.method(:zz).call, (o.yy rescue $!.class)] }
