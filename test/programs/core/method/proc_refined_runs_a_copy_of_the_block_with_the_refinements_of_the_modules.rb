# Proc#refined (ruby 4.1) returns a copy of the Proc whose body runs with
# the refinements of the given modules, the last one's first; the
# receiver is left as it is. Chains add their modules. Blocks and
# methods that the body writes keep the refinements after it returns.
# Errors: a non-Module, a Proc with no Ruby block, define_method, and
# using in the body.
$stdout.sync = true
module Shout; refine(String) { def shout = upcase + "!" }; end
module Quiet; refine(String) { def shout = downcase; def quiet = "..." }; end
def t(label) = (p [label, yield] rescue p [label, $!.class, $!.message])
pr = -> s { s.shout }
t(:basic) { pr.refined(Shout).call("hi") }
t(:orig) { pr.call("hi") }
t(:chain) { pr.refined(Shout).refined(Quiet).call("Hi") }
t(:chain2) { -> s { [s.shout, s.quiet] }.refined(Shout).refined(Quiet).call("Hi") }
t(:none) { pr.refined.equal?(pr) }
t(:int) { pr.refined(42) }
t(:cls) { pr.refined(String) }
t(:sym) { :upcase.to_proc.refined(Shout) }
t(:meth) { "x".method(:upcase).to_proc.refined(Shout) }
t(:eq) { r = pr.refined(Shout); [r == pr, r.eql?(pr), r.hash == pr.hash, r == pr.refined(Shout)] }
t(:dm) { Class.new { define_method(:m, pr.refined(Shout)) } }
t(:using) { proc { using Quiet }.refined(Shout).then { |r| Module.new.module_eval(&r) } }
t(:after) { r = -> { -> { "x".shout } }.refined(Shout); r.call.call }
t(:def_after) { o = Object.new; -> { def o.sh = "q".shout }.refined(Shout).call; o.sh }
t(:yield) { def y1 = yield("z"); y1(&pr.refined(Shout)) }
t(:each) { %w[a b].map(&pr.refined(Shout)) }
t(:iexec) { Object.new.instance_exec(&proc { "i".shout }.refined(Shout)) }
t(:inspect) { pr.refined(Shout).inspect.sub(/0x\h+/, "X").sub(/\S+:/, "F:") }
t(:source) { [pr.refined(Shout).source_location == pr.source_location, pr.refined(Shout).lambda?, pr.refined(Shout).arity] }
t(:frozen) { pr.freeze.refined(Shout).frozen? }
t(:args) { pr.method(:refined).arity }
t(:binding) { pr.refined(Shout).binding.local_variable_defined?(:pr) }
t(:sendshout) { -> s { s.send(:shout) }.refined(Shout).call("x") }
t(:respond) { -> s { s.respond_to?(:shout) }.refined(Shout).call("x") }
t(:mm) { -> s { s.method(:shout).call }.refined(Shout).call("x") }
t(:curry) { ->(a, b) { a.shout + b }.refined(Shout).curry["a"]["b"] }
t(:nested_refined) { -> { -> { "n".shout }.refined(Quiet).call }.refined(Shout).call }
