# A `require_relative` written in a METHOD body loads its target when the
# method RUNS, even when some other site has already made that file a unit.
#
# The guard below makes `part.rb` a unit-only target: it is never spliced, and
# every site naming it keeps its call so that whichever one runs first loads
# the body once. The method-body site is the only one that ever runs here.

require_relative "method_body_require/part" if ENV["NEVER"]

def load_part
  require_relative "method_body_require/part"
end

p defined?(PART)
p load_part
p defined?(PART)
p PART
# A second call answers false: the feature is loaded.
p load_part
