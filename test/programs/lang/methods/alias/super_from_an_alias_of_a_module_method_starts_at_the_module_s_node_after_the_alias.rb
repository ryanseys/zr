# An alias in a class of a module's method finds the module's node when it
# runs: the first one from the alias's class up, which a module prepended
# to that class is (aliased_callable_method_entry). Its super and its
# super_method go on from there.
module M
  def m = [:Mm, *(defined?(super) ? super : [])]
  def n = [:Mn, *super]
end
class C
  prepend M
  def m = :C
end
class SC < C
  alias n m
  prepend M
end
p SC.new.n
p SC.new.method(:n).super_method&.owner
class SSC < SC
  prepend M
  def n = [:SSC, *super]
end
class SSSC < SSC
  alias o n
  prepend M
end
p SSSC.new.o
p SSSC.new.method(:o).owner, SSSC.new.method(:o).super_method&.owner
module P; def x = [:P, *(defined?(super) ? super : [])]; end
class D; include P; end
class E < D; alias y x; include P; end
p E.new.y
class F; include P; alias z x; end
class G < F; include P; end
p G.new.z
