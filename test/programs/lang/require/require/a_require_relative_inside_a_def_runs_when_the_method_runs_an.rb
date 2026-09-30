# A `require_relative` written inside a `def` runs when the METHOD runs, not
# where the file that defines it is loaded. So the target's constants are
# absent until the first call, the first call answers true and the second
# false, and a program that never calls the method never loads the file.
def pull = require_relative("require_relative_in_method/counted")

p defined?(COUNTED_RUNS)
p pull
p pull
p COUNTED_RUNS

def never_called = require_relative("require_relative_in_method/late")

p defined?(Late)
p never_called
p Late.name_of
