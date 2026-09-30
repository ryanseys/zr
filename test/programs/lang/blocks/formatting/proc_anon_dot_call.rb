# `proc { ... }.call` — the receiver is the inline `proc { ... }` call,
# not a local variable holding the proc. Any receiver that is a Proc
# works the same way.
#
# Coverage scope:
# - Anonymous proc literal `.call`
# - Anonymous proc with args
# - Method returning a proc, immediately called (factory pattern)
# - Ternary returning a proc
#
# Out of scope (other examples cover these):
# - lambda { ... }.call / ->() { ... }.()
# - @ivar = proc { ... }; @ivar.call
# - $global = proc { ... }; $global.call
# - [proc1, proc2].each(&:call)

def show(s)
  puts s
end

# Anonymous proc literal.
proc { show("anon") }.call
proc { show("second") }.call
proc { |n| show((n * 2).to_s) }.call(7)

# CallNode receiver returning a proc (factory pattern).
def factory
  proc { show("factory") }
end
factory.call

# Ternary returning a proc — both branches must unify to `proc`.
cond = true
(cond ? proc { show("ternary-true") } : proc { show("ternary-false") }).call
