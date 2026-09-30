# `rescue => e` inside a lambda / proc body binds `e` as a body-local
# exception, and `#{e.message}` interpolates the message String. The
# test prints inside the body, so it does not depend on the value that
# the call returns.
lambda { begin; raise "a"; rescue => e; puts "got #{e.message}"; end }.call
proc { begin; raise "boom"; rescue => e; puts "p #{e.message} (#{e.class})"; end }.call

# Same construct, stored then called.
f = lambda { begin; raise "late"; rescue => e; puts "f: #{e.message}"; end }
f.call

# A non-raising path through the body runs too.
g = proc { begin; puts "no raise"; rescue => e; puts "unreached #{e.message}"; end }
g.call
