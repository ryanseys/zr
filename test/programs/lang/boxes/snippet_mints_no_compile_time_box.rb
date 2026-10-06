

# `Ruby::Box.new` in a SNIPPET mints a real box.
#
# `box = Ruby::Box.new` at a program's top level allocates a COMPILE-TIME
# box: the loader mints it, binds the local to its surrogate, and splices
# every `box.require` into the program. A snippet's cannot be one -- the
# handle would name a box nothing else in the program can reach -- so it
# stays the ordinary call, and reaches `Ruby::Box`'s own constructor,
# which mints at run time. The snippet runs; it is not refused.

def show(src)
  puts eval([src, "nil"].first).inspect
rescue Exception => e
  puts "#{e.class}: #{e.message}"
end

show("b = Ruby::Box.new; b.class.to_s")
show("Ruby::Box.new.class.to_s")
