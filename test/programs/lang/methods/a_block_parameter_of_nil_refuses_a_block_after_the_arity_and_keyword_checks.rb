# ruby 4.1's `&nil` block parameter: a def, a block, a lambda or a
# define_method body with `&nil` raises ArgumentError "no block accepted"
# for a block given, after the arity and keyword checks, and lists
# [:noblock] in its parameters.
def t(label)
  p [label, yield]
rescue Exception => e
  p [label, e.class, e.message, e.backtrace_locations&.first&.label]
end
def m(&nil) = :ok
def m2(a, b = 1, *r, k: 2, **o, &nil) = [a, b, r, k, o]
t(:plain) { m }
t(:brace) { m { } }
t(:amp_nil) { m(&nil) }
t(:amp_proc) { m(&proc {}) }
t(:amp_method) { m(&method(:puts)) }
t(:m2) { m2(1, 2, 3, k: 4, z: 5) }
t(:m2_block) { m2(1) { } }
t(:params) { method(:m).parameters }
t(:params2) { method(:m2).parameters }
t(:arity) { [method(:m).arity, method(:m2).arity] }
t(:inspect) { method(:m).inspect.sub(/ \S+:\d+>/, ">") }
t(:inspect2) { method(:m2).inspect.sub(/ \S+:\d+>/, ">") }
pr = proc { |a, &nil| a }
t(:proc_params) { pr.parameters }
t(:proc_call) { pr.call(1) }
t(:proc_call_block) { pr.call(1) { } }
t(:proc_inspect) { pr.inspect.sub(/0x\h+ \S+:\d+/, "X") }
t(:proc_arity) { [pr.arity, pr.lambda?] }
l = ->(&nil) { 1 }
t(:lambda_params) { l.parameters }
t(:lambda_call_block) { l.call { } }
t(:lambda_call) { l.() }
t(:yield_proc) { def y1 = yield; y1 { |&nil| 3 } }
class C; define_method(:dm) { |&nil| :dm }; end
t(:define_method) { C.new.dm }
t(:define_method_block) { C.new.dm { } }
t(:dm_params) { C.instance_method(:dm).parameters }
class P; def m(&b) = b; end
class Q < P; def m(&nil) = super; end
t(:zsuper) { Q.new.m }
class Q2 < P; def m(&nil) = super(); end
t(:super_parens) { Q2.new.m }
t(:send) { send(:m) { } }
t(:public_send) { public_send(:m) { } }
t(:method_call) { method(:m).call { } }
t(:to_proc) { method(:m).to_proc.call { } }
t(:block_given) { def bg(&nil) = block_given?; bg }
t(:respond) { m(*[]) }
def kw(k:, &nil) = k
t(:kw_block) { kw(k: 1) { } }
t(:kw_missing_block) { kw { } }
t(:argc_and_block) { m(1) { } }
t(:instance_exec) { instance_exec(1) { |a, &nil| a } }
t(:each) { [1, 2].map { |x, &nil| x * 2 } }
t(:eval_def) { eval("def ev(a, &nil) = a"); [ev(1), method(:ev).parameters] }
t(:eval_block) { ev(1) { } }
t(:eval_proc) { eval("proc { |x, &nil| x }").call(2) { } }
t(:singleton) { o = Object.new; def o.s(&nil) = 1; [o.s, (o.s { } rescue $!.message)] }
t(:yield_inside) { def yi(&nil) = (yield rescue $!.class); yi }
t(:nested_block) { def nb(&nil) = [1].map { |x| x + 1 }; nb }
t(:args_rest) { def ar(*a, **k, &nil) = [a, k]; [ar(1, b: 2), (ar(1) { } rescue $!.message)] }
t(:unknown_kw_first) { def uk(a, &nil) = a; uk(1, z: 1) { } }
t(:too_many_first) { def tm(a, &nil) = a; tm(1, 2) { } }
t(:proc_no_args) { proc { |&nil| :pna }.call { } }
t(:proc_no_args_ok) { proc { |&nil| :pna }.call(1, 2) }
t(:lambda_no_args_arity) { ->(&nil) { }.call(1) }
t(:proc_inspect_params) { proc { |&nil| }.parameters }
t(:curry) { ->(a, b, &nil) { a + b }.curry[1][2] }
t(:method_unbind) { method(:m).unbind.bind_call(self) }
t(:super_into_nil) { class S1; def m(&nil) = :s1; end; class S2 < S1; def m = super; end; [S2.new.m, (S2.new.m { } rescue $!.message)] }
