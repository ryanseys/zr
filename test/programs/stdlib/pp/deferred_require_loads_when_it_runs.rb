# A `require` written inside a METHOD body defines its feature's constants
# when the method RUNS, exactly as CRuby does -- not before the program's
# first statement.
#
# So `defined?(PrettyPrint)` is nil before the first call to `lazy`. The
# first `require` returns true, and the second returns false.

def lazy
  require "prettyprint"
end

p defined?(PrettyPrint)
p lazy
p defined?(PrettyPrint)
p lazy
