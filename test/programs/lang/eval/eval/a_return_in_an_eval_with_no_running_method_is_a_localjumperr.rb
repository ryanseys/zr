# A return in an eval leaves the method that holds the scope. With no
# such method running, it is a LocalJumpError, except straight in the
# toplevel, where it ends the file.
def mk = proc { eval("return :orphan") }
begin; mk.call; rescue LocalJumpError => e; p [:orphan, e.message, e.exit_value]; end
pr = proc { eval("return 1") }
begin; pr.call; rescue LocalJumpError => e; p [:top_proc, e.message]; end
begin; [1].each { eval("return 2") }; rescue LocalJumpError => e; p [:top_block, e.message]; end
begin; class Foo; eval("return 3"); end; rescue LocalJumpError => e; p [:class_body, e.message]; end
def m = ([1].each { eval("return :m") }; :no)
p m
at_exit { puts "at_exit" }
eval("return 4")
puts "not reached"
