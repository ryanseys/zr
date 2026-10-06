# TracePoint#defined_class is the class where the call found the
# method: through a module, a prepend, a module function and a
# singleton, and for a def that an eval of the same string defines
# again on a new class.
module M; def m = 1; module_function def mf = 2; end
module P; def pp1 = super; end
class C; include M; def c = 3; def pp1 = 4; end
C.prepend(P)
class D < C; def d = super rescue 0; end
o = D.new
s = Object.new
def s.sing = 5
ev = []
TracePoint.new(:call, :line) { |tp| ev << [tp.event, tp.method_id, tp.defined_class] if tp.path == __FILE__ }.enable do
  o.m; o.c; o.pp1; M.mf; s.sing; o.d
end
ev.each { p _1.map { |x| x.is_a?(Module) && x.singleton_class? ? :singleton : x } }

class T
  def run
    events = []
    trace = nil
    eval <<-EOF.gsub(/^.*?: /, ""), nil, 'xyzzy'
    1: trace = TracePoint.trace(:line, :call) { |tp| events << [tp.event, tp.lineno, tp.defined_class, tp.self] if tp.path == 'xyzzy' }
    2: class XYZZY
    3:   def foo
    4:     1
    5:   end
    6: end
    7: xyzzy = XYZZY.new
    8: xyzzy.foo
    9: trace.disable
    EOF
    self.class.class_eval { remove_const(:XYZZY) }
    events
  end
end
t = T.new
2.times do
  ev = t.run
  foo = ev.select { |e| e[1] == 4 || e[0] == :call }
  p foo.map { |e| [e[0], e[2].equal?(e[3].class)] }
end
