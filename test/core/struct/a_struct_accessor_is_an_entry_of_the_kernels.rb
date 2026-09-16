# A Struct member's reader and writer are entries of the kernel's, with
# no frame of their own: the arity error is the caller's, a trace sees
# a C call, the writer's one parameter is `_`, and an allocated struct
# reads nil and takes a write; Data's readers are the same entries.
S = Struct.new(:a, :b)
s = S.new(1, 2)
begin; s.a(2); rescue ArgumentError => e; puts e.message; puts e.backtrace.first(2); end
begin; s.send(:a=, 1, 2); rescue ArgumentError => e; puts e.message; puts e.backtrace.first(2); end
begin; s.a(k: 1); rescue ArgumentError => e; puts e.message; end
begin; s.freeze.a = 3; rescue => e; puts e.class, e.message; end
m = S.instance_method(:a)
p m.source_location, m.owner, m.inspect, m.arity, m.parameters, S.instance_method(:a=).inspect
ev = []
tp = TracePoint.new(:call, :return, :c_call, :c_return) { |t| ev << [t.event, t.method_id] if %i[a a=].include?(t.method_id) }
t = S.new(5, 6)
tp.enable { t.a; t.a = 1 }
p ev
class T < S
  def a = super + 100
  def a=(v); super(v * 2); end
end
u = T.new(1, 2)
u.a = 3
p u.a, u.to_a
x = S.allocate
p x.a
x.b = 9
p x.to_a
D = Data.define(:q)
p D.new(q: 1).q, D.instance_method(:q).parameters, D.instance_method(:q).source_location
p S.instance_method(:a).bind(T.new(7, 8)).call
begin; S.instance_method(:a).bind(Object.new); rescue TypeError => e; puts e.message; end
p s.respond_to?(:a=), S.public_instance_methods(false).sort
p s.method(:a).to_proc.lambda?, s.method(:a).to_proc.call
p S.new(1).a, (S.new(1, 2, 3) rescue $!.message)

__END__
wrong number of arguments (given 1, expected 0)
core/struct/a_struct_accessor_is_an_entry_of_the_kernels.rb:7:in '<main>'
wrong number of arguments (given 2, expected 1)
core/struct/a_struct_accessor_is_an_entry_of_the_kernels.rb:8:in '<main>'
wrong number of arguments (given 1, expected 0)
FrozenError
can't modify frozen S: #<struct S a=1, b=2>
nil
S
"#<UnboundMethod: S#a()>"
0
[]
"#<UnboundMethod: S#a=(_)>"
[[:c_call, :a], [:c_return, :a], [:c_call, :a=], [:c_return, :a=]]
106
[6, 2]
nil
[nil, 9]
1
[]
nil
7
bind argument must be an instance of S
true
[:a, :a=, :b, :b=]
true
1
1
"struct size differs"
