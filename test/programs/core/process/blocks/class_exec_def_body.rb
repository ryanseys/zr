# class_exec / module_exec with a method-defining block is the same
# reopen of the class as class_eval with such a block.
class C; end
C.class_exec { def hi; 3; end }
p(C.new.hi)
module M; end
M.module_exec { def mm; 4; end }
class D; include M; end
p D.new.mm
