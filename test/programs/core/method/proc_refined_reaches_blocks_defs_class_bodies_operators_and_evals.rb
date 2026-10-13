# Proc#refined in the shapes of ruby/spec: several modules and their
# order, a shared closure, lambda-ness and arity, a Proc subclass,
# nested blocks, defs, Class.new and class bodies, &:sym, operators and
# element access, instance_eval/exec and class_eval, dup and clone,
# equality and hash, define_singleton_method, break and next, threads
# and fibers.
$stdout.sync = true
module Shout; refine(String) { def shout = upcase + "!" }; end
module Quiet; refine(String) { def shout = downcase; def quiet = "..." }; end
module Operators
  refine(Integer) { def +(o) = "plus(#{self},#{o})"; def <(o) = "lt" }
  refine(Array) { def [](i) = "at#{i}" }
  refine(Hash) { def [](k) = "aref(#{k})" }
end
class ClassBodyHost; end
def t(label) = (p [label, yield] rescue p [label, $!.class, $!.message])
t(:multi) { -> s { [s.shout, s.quiet] }.refined(Shout, Quiet).call("Hi") }
t(:order1) { -> s { s.shout }.refined(Shout, Quiet).call("Hi") }
t(:order2) { -> s { s.shout }.refined(Quiet, Shout).call("Hi") }
t(:env) { c = 0; pr = -> { c += 1 }; pr.refined(Shout).call; pr.call; c }
t(:lambda) { l = -> s { s }.refined(Shout); [l.lambda?, l.arity, proc { |s| s }.refined(Shout).lambda?] }
t(:subclass) { sc = Class.new(Proc); r = sc.new { |s| s.shout }.refined(Shout); [r.instance_of?(sc), r.call("hi")] }
t(:singleton) { pr = -> s { s.shout }; def pr.tag = :orig; r = pr.refined(Shout); [r.respond_to?(:tag), r.call("hi")] }
t(:nested) { -> a { a.map { |s| s.shout } }.refined(Shout).call(%w[a b]) }
t(:defs) { -> { o = Object.new; def o.sh = "hi".shout; o.sh }.refined(Shout).call }
t(:class_new) { -> { Class.new { def sh = "hi".shout }.new.sh }.refined(Shout).call }
t(:class_kw) { -> { class ClassBodyHost; def sh = "hi".shout; end; ClassBodyHost.new.sh }.refined(Shout).call }
t(:symproc) { pr = -> a { a.map(&:shout) }; [pr.refined(Shout).call(%w[a b]), (pr.call(%w[a]) rescue $!.class)] }
t(:ops) { [-> a, b { [a + b, a < b] }.refined(Operators).call(1, 2), -> a { a[0] }.refined(Operators).call([9]), -> h { h["x"] }.refined(Operators).call({ "x" => 1 }), -> a, b { a + b }.call(1, 2)] }
t(:evals) { r = proc { "hi".shout }.refined(Shout); [Object.new.instance_eval(&r), Object.new.instance_exec(&r), Class.new.class_eval(&r)] }
t(:dup) { r = -> s { s.shout }.refined(Shout); [r.dup.call("hi"), r.clone.call("hi")] }
t(:ne) { pr = -> s { s.shout }; r1 = pr.refined(Shout); r2 = pr.refined(Quiet); [r1 == r2, r1 == pr.refined(Shout)] }
t(:hash) { pr = -> s { s.shout }; r = pr.refined(Shout); h = { pr => :s, r => :r }; b = r.hash; r.call("hi"); [h.size, r.hash == b, h[r]] }
t(:dsm) { Object.new.define_singleton_method(:m, -> s { s }.refined(Shout)) }
t(:refine_in) { -> s { Module.new { refine(String) { def whisper = downcase } }; s.shout }.refined(Shout).call("hi") }
t(:orig_after) { "q".shout }
t(:recursion) { f = nil; f = ->(n) { n.zero? ? "r".shout : f.(n - 1) }.refined(Shout); f.(3) }
t(:raise) { -> { raise "boom" }.refined(Shout).call }
t(:after_raise) { "q".shout }
t(:break) { [1, 2].each(&proc { break :b }.refined(Shout)) }
t(:next) { [1, 2].map(&proc { |x| next x * 2 }.refined(Shout)) }
t(:thread) { Thread.new { -> { "t".shout }.refined(Shout).call }.value }
t(:fiber) { Fiber.new { -> { Fiber.yield "f".shout; "g".shout }.refined(Shout).call }.then { |f| [f.resume, f.resume] } }
t(:parameters) { ->(a, b = 1, *c, d:, &e) {}.refined(Shout).parameters }
