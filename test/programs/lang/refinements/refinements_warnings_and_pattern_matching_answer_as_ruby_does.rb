def t(l)
  r = yield
  puts "#{l}: #{r.inspect}"
rescue Exception => e
  puts "#{l}: !#{e.class}: #{e.message[0, 300]}"
end

module RefA; refine(String) { def ra = :ra; def to_s = "refined" }; end
module Helpers; def helper = :h; end
module RefB; refine(Array) { import_methods Helpers }; end
using RefA
using RefB
t(:refined_send) { ["".ra, "".send(:ra), ("".public_send(:ra) rescue $!.class), "".respond_to?(:ra), ("".method(:ra).call rescue $!.class)] }
t(:refined_symproc) { %w[x].map(&:ra) }
t(:import_methods) { [].helper }
t(:refinements_api) { [RefA.refinements.map(&:target), Module.used_modules, RefA.refinements.first.class] }
t(:refined_to_s_interp) { "#{"abc"}" }
t(:refine_module) { module RM; refine(Enumerable) { def rme = :rme }; end; using RM; [1].rme }
t(:warning_override) { r = []; Warning.singleton_class.alias_method(:orig_warn, :warn); Warning.define_singleton_method(:warn) { |m, category: nil, **| r << [m.chomp, category] }; warn "hello"; warn "dep", category: :deprecated; Warning[:deprecated] = true; warn "dep2", category: :deprecated; Warning.singleton_class.alias_method(:warn, :orig_warn); r }
t(:warning_categories) { Warning.categories }
t(:warning_bad_cat) { warn "x", category: :nope }
t(:pm_nomatch_msg) { case [1, 2]; in [a] then a end }
t(:pm_key_err) { {a: 1} => {b:} }
t(:pm_deconstruct_keys_nil) { c = Class.new { def deconstruct_keys(k) = {x: k} }; case c.new; in {x:} then x end }
t(:pm_pin_ivar) { @iv = 1; case 1; in ^@iv then :ok end }
t(:pm_in_bool) { [(1 in Integer), ("s" in Integer)] }
t(:pm_guard_unless) { case 3; in Integer => n unless n > 5 then n end }
t(:pm_array_splat_pin) { x = [1, 2]; case [1, 2]; in ^x then :pinned end }
t(:pm_find_err) { case [1, 2]; in [*, 3, *] then 1 end }
t(:pm_hash_rest) { case {a: 1, b: 2}; in {a:, **rest} then rest end }
t(:pm_const_paren) { case 5; in Integer(5..) then :y end rescue $!.class }
t(:pp_nested) { require "pp"; PP.pp({list: (1..30).to_a, nested: {deep: {deeper: ["a" * 30, "b" * 30]}}, str: "x"}, +"", 50) }
t(:pp_struct_data) { require "pp"; D2 = Data.define(:alpha, :beta); S2 = Struct.new(:gamma, :delta); PP.pp([D2.new(alpha: "a" * 30, beta: [1] * 10), S2.new("g" * 30, {k: 1})], +"", 40) }
t(:pp_set) { require "pp"; PP.pp(Set.new(1..40), +"", 40) }
t(:pp_cycle) { require "pp"; a = [1]; a << a; h = {a: a}; PP.pp(h, +"", 20) }
t(:inspect_ivars_order) { o = Object.new; o.instance_variable_set(:@z, 1); o.instance_variable_set(:@a, [o]); o.inspect.gsub(/0x\h+/, "X") }
t(:inspect_custom_ivars) { c = Class.new { def initialize = (@a = 1; @b = 2); private def instance_variables_to_inspect = [:@b] }; c.new.inspect.gsub(/0x\h+/, "X") }
t(:full_message_variants) { e = (raise "m" rescue $!); [e.full_message(highlight: true, order: :bottom).lines.size, e.full_message(highlight: true).include?("\e[1m"), e.detailed_message(highlight: true)] }
t(:exception_to_s_nil) { [RuntimeError.new(nil).message, RuntimeError.new(5).message, (raise IOError rescue $!.message)] }
t(:exception_exception) { e = RuntimeError.new("a"); [e.exception.equal?(e), e.exception("b").message, e.exception("b").equal?(e)] }
t(:exception_backtrace_set) { e = RuntimeError.new; e.set_backtrace(["a:1"]); [e.backtrace, e.backtrace_locations] }
t(:exception_bt_locations_set) { e = RuntimeError.new; e.set_backtrace(caller_locations(0, 1)); e.backtrace_locations.class }
t(:frozen_error_receiver) { begin; "x".freeze << "y"; rescue FrozenError => e; [e.receiver, e.message]; end }
t(:nomethod_args) { begin; nil.foo(1, 2); rescue NoMethodError => e; [e.args, e.private_call?, e.name]; end }
t(:name_error_local) { begin; undefined_local_zz; rescue NameError => e; [e.name, e.local_variables.class, e.message]; end }
t(:key_error_custom) { KeyError.new("m", receiver: {}, key: :k).then { [_1.receiver, _1.key] } }
t(:stop_iteration_result) { e = [1].each; e.next; begin; e.next; rescue StopIteration => s; s.result; end }
t(:systemexit) { begin; exit 3; rescue SystemExit => e; [e.status, e.success?, e.message]; end }
t(:uncaught_throw) { begin; throw :zz, 1; rescue UncaughtThrowError => e; [e.tag, e.value, e.message]; end }
t(:errno_new) { [Errno::ENOENT.new.message, Errno::ENOENT.new("x").message, Errno::ENOENT::Errno, SystemCallError.new("m", 2).class, SystemCallError.new(nil, 99999).message] }
t(:signal_exception) { [SignalException.new("INT").signo, SignalException.new(15).message, Interrupt.new.signo] }
t(:nested_cause_cycle) { begin; begin; raise "a"; rescue => a; raise "b"; end; rescue => b; begin; raise a, cause: b; rescue => c; [c.message, c.cause&.message]; end; end }
