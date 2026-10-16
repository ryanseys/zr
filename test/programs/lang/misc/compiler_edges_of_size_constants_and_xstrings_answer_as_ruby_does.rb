def t(l)
  r = yield
  puts "#{l}: #{r.inspect}"
rescue Exception => e
  puts "#{l}: !#{e.class}: #{e.message[0, 200]}"
end

module RU; refine(Integer) { def rr = :refined }; end
t(:using_in_block) { m = Module.new { using RU; def self.q = 1.rr }; m.q }
t(:using_send) { Module.new.send(:using, RU) }
t(:many_args) { def m12(a, b, c, d, e, f, g, h, i, j, k, l) = [a, l]; m12(*1..12) }
t(:many_args_direct) { def m10(a, b, c, d, e, f, g, h, i, j) = a + j; m10(1, 2, 3, 4, 5, 6, 7, 8, 9, 10) }
t(:many_kwargs) { def mk(a:, b:, c:, d:, e:, f:, g:, h:, i:, j:) = [a, j]; mk(a: 1, b: 2, c: 3, d: 4, e: 5, f: 6, g: 7, h: 8, i: 9, j: 10) }
t(:many_block_args) { proc { |a, b, c, d, e, f, g, h, i, j| [a, j] }.call(*1..10) }
t(:huge_method) { eval("def huge; x = 0; " + (1..3000).map { "x += #{_1}; " }.join + "x; end"); huge }
t(:deep_nesting) { eval("[" * 500 + "1" + "]" * 500).flatten }
t(:big_literal) { a = eval("[" + (1..20000).to_a.join(",") + "]"); a.sum }
t(:big_frame) { eval("def bigf; " + (1..2000).map { "v#{_1} = #{_1}" }.join("; ") + "; v1 + v2000; end"); bigf }
t(:case_big) { eval("def cb(x); case x; " + (1..500).map { "when #{_1} then #{_1 * 2}" }.join("; ") + "; end; end"); cb(499) }
t(:string_huge_interp) { x = 1; eval('"' + '#{x}' * 2000 + '"').size }
t(:const_dyn) { o = Module.new; o::K = 1; o::K }
t(:const_dyn2) { def mod_of = Module.new; mod_of::Z = 3 }
module ConstDyn3; end
t(:const_dyn3) { m = ConstDyn3; m::A ||= 2; m::A += 1; m::A }
t(:singleton_def_expr) { o = Object.new; def (o).zz = 9; o.zz }
t(:class_expr_super) { Class.new([String, Array].last) { def x = size }.new([1]).x }
t(:class_reopen_mismatch) { class String2 < String; end; class String2 < Array; end }
t(:xstring_interp) { x = "echo hi"; `#{x}` }
t(:xstring_redef) { def `(c) = "cmd:#{c}"; `ls` }
t(:redo) { i = 0; r = []; [1, 2].each { |x| i += 1; r << x; redo if i == 1 }; r }
t(:retry_loop) { n = 0; begin; n += 1; raise if n < 3; rescue; retry; end; n }
t(:break_from_proc) { pr = proc { break 1 }; pr.call }
t(:next_in_method_block) { [1, 2].map { next 0 if _1 == 1; _1 } }
t(:return_from_lambda) { -> { return 5 }.call }
t(:return_from_proc_toplevel) { proc { return 7 }.call }
t(:return_orphan) { def mkp = proc { return 1 }; mkp.call }
t(:begin_end_block) { eval("BEGIN { $bb = 1 }; $bb") }
t(:end_block) { eval("END { puts 'END ran' }"); :ok }
t(:flipflop3) { (1..8).select { (_1 == 2)...(_1 == 2) } }
t(:match_last_line) { $_ = "abc"; if /b/ then :y end }
t(:gets_dollar_underscore) { $_ = "x"; print; :printed }
t(:numbered_param_nested) { [[1]].map { _1.map { it + 1 } } }
t(:pattern_complex) { case [1, {k: [2, 3]}]; in [Integer => a, {k: [*, 3 => b]}] if a < b then [a, b] end }
t(:pattern_alt) { case 5; in 1 | 5 | 7 then :y end }
t(:pattern_nil) { case {a: nil}; in {a: nil, **nil} then :exact end }
t(:pattern_deconstruct_cache) { c = Class.new { attr_reader :n; def initialize = @n = 0; def deconstruct = (@n += 1; [1, 2]) }; o = c.new; case o; in [0, _] then 0; in [1, _] then 1 end; o.n }
t(:ensure_return) { def er; return 1; ensure; puts "ens"; end; er }
t(:ensure_break) { [1].each { begin; break 2; ensure; puts "e2"; end } }
t(:super_implicit_args) { c = Class.new { def m(a, b = 2, *r, k: 1, &blk) = [a, b, r, k] }; d = Class.new(c) { def m(a, b = 5, *r, k: 3, &blk) = (a = 9; super) }; d.new.m(1) }
t(:super_in_block) { c = Class.new { def m(x) = x }; d = Class.new(c) { def m(x) = [1].map { super(x + 1) } }; d.new.m(1) }
t(:super_define_method) { c = Class.new { def m = :base }; d = Class.new(c) { define_method(:m) { super() } }; d.new.m }
t(:super_implicit_define_method) { c = Class.new { def m = :base }; d = Class.new(c) { define_method(:m) { super } }; d.new.m }
t(:method_added_alias) { r = []; Class.new { define_singleton_method(:method_added) { r << _1 }; def a = 1; alias b a; alias_method :c, :a; attr_accessor :d }; r }
t(:op_methods) { c = Class.new { def +@ = :up; def -@ = :neg; def ! = :not; def =~(o) = :match; def [](*a) = a; def []=(*a); a; end; def call(*) = :called; def to_proc = proc { :tp } }; o = c.new; [+o, -o, !o, o =~ 1, o[1, 2], (o[1] = 2), o.(1), [1].map(&o)] }
t(:safe_nav_assign) { o = nil; o&.x = 1; o&.x += 1 rescue $!.class }
t(:multiple_return) { def mr = return 1, 2; mr }
t(:splat_hash_last) { def sh(*a) = a; sh(*[1, {a: 1}]) }
t(:kwsplat_nil) { def kn(**nil) = :ok; [kn, (kn(a: 1) rescue $!.message)] }
t(:block_kw) { proc { |a, b: 2| [a, b] }.call(1, b: 3) }
t(:proc_auto_splat) { [[1, 2]].map { |a, b| b } }
t(:lambda_strict) { ->(a, b) { }.call([1, 2]) }
t(:yield_multiple) { def ym = yield(1, 2); ym { |a| a } }
t(:block_pass_method) { [1, 2].map(&method(:Integer)) }
t(:ruby2_keywords) { ruby2_keywords def r2k(*a) = a; r2k(k: 1).last.class }
t(:obj_frozen_mod) { Comparable.frozen? }
t(:globals) { [$stdout.class, $;, $,, $/, $\, $0.class, $*.class, $$.class, $PROGRAM_NAME.class, global_variables.include?(:$stdout)] }
t(:gvar_alias) { $orig = 1; eval("alias $ali $orig"); $ali }
t(:trace_var) { r = []; trace_var(:$tv) { r << _1 }; $tv = 5; untrace_var(:$tv); r }
t(:special_gvars) { "abc" =~ /(b)/; [$~[0], $1, $`, $', $+, $&, $LAST_MATCH_INFO.class] rescue $!.class }
t(:dollar_bang) { begin; raise "x"; rescue; [$!.message, $@.class]; end }
t(:dollar_semicolon) { $; = ","; "a,b".split } 
t(:obsolete_gvar) { $= }
