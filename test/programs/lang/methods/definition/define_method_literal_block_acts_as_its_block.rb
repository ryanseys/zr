# A define_method call with a block literal: a send of the method runs
# the body directly. It must act as the block that the method runs: the
# same frame label, self, captured locals, parameters, arity errors,
# keywords, super, return, and the cref of the method.
total = 0
class Base
  def greet(x) = "base #{x}"
end

class Kid < Base
  K = :kid
  define_method(:zero) { 0 }
  define_method(:one) { |arg| arg }
  define_method(:label) { caller_locations(0, 1)[0].label }
  define_method(:name) { __method__ }
  define_method(:me) { self }
  define_method(:params) { |x = 1, *r, k: 2, **o, &blk| [x, r, k, o, blk&.call] }
  define_method(:greet) { |x| super(x) + " kid" }
  define_method(:early) { |x| return :neg if x < 0; :pos }
  define_method(:stop) { |x| break x * 2 }
  define_method(:const) { K }
  define_method(:fail) { raise "boom" }
  define_method(:defs) { |x| x.respond_to?(:upcase) ? x.upcase : x }
end

k = Kid.new
p k.zero, k.one(5), k.label, k.name, k.me.equal?(k)
p k.params, k.params(3, 4, 5, k: 6, z: 7) { :blk }
p k.greet(1), k.early(-1), k.early(1), k.stop(21), k.const
begin
  k.fail
rescue => e
  p e.message, e.backtrace[0][/'.*'/]
end
begin
  k.one
rescue ArgumentError => e
  p e.message
end
begin
  k.zero(1)
rescue ArgumentError => e
  p e.message
end
p Kid.instance_method(:params).parameters, Kid.instance_method(:one).arity
p k.defs("a"), k.defs(1)

# The body captures a local of the scope around it.
seen = []
Kid.define_method(:note) { |x| seen << x; total += x }
k.note(2)
k.note(3)
p seen, total

# A copy of the method (alias, a Method) runs the same body.
class Kid
  alias_method :uno, :one
  define_method(:dos, instance_method(:one))
end
p k.uno(7), k.dos(8), k.method(:one).call(9), k.public_send(:one, 10)
p k.method(:one) == k.method(:one), k.method(:one) == k.method(:uno)

# Keywords as a Hash argument, and ruby2_keywords.
class Kid
  define_method(:rest) { |*a| a }
  ruby2_keywords(:rest)
  define_method(:pass) { |*a| target(*a) }
  ruby2_keywords(:pass)
  def target(*a, **kw) = [a, kw]
end
p k.rest(1, a: 2), k.pass(1, b: 3)

# A body redefined by a plain def, and the other way.
class Kid
  def zero = :def
end
p k.zero
class Kid
  define_method(:zero) { :again }
end
p k.zero

# Many calls.
n = 0
i = 0
while i < 1000
  n += k.one(i) + k.zero.to_s.size
  i += 1
end
p n
