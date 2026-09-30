# A main-only class/constant is INVISIBLE inside a box (boxes dup from
# MASTER, not main): resolving it inside box.eval raises NameError-shaped
# failures rather than leaking main's definitions.



MAIN_ONLY = 42
box = Ruby::Box.new
box.eval("begin; p MAIN_ONLY; rescue NameError => e; puts 'invisible'; end")
