# A trap command given as a String runs as Ruby in the scope that the
# signal interrupted (the innermost Ruby frame): its locals, its method,
# its file and line and its lexical scope, with the main object as self.
# (zr shows the frame's locals only where the frame keeps them:
# test/gaps/a_string_trap_command_sees_the_interrupted_methods_locals.rb.)
def x = :method_x

trap(:USR1, "p [__FILE__ == $0, __LINE__, __method__, x, self]")
def m(y)
  z = y + 1
  Process.kill(:USR1, $$)
  z
end
m(1)

class Foo
  trap(:USR2, "p [Module.nesting, self]")
  Process.kill(:USR2, $$)
end

trap(:HUP, "raise 'from the command'")
begin
  Process.kill(:HUP, $$)
rescue => e
  p e.message
end
