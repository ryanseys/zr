# The RUN-TIME compiler on shapes real gems use. A `require` whose target only
# the running program knows -- a computed feature name, or one reached through
# a `$LOAD_PATH` the program just changed -- is compiled at run time by a
# second compiler. This checks two ordinary things there.
#
# AN ALIAS THROUGH `extend`. An aliased method reached through `extend` runs
# with the CLASS as `self`, so a receiverless call inside it finds a method of
# the class, not an INSTANCE method. Forwardable is exactly this --
# `alias def_delegators def_instance_delegators` -- so
# `extend Forwardable; def_delegators :@t, :year` must work.
#
# A GUARDED TOP-LEVEL DEFINITION. A top-level `def` inside an `if` in a file
# that the run time compiles. `time.rb` has this shape, and
# `require "bundler/setup"` loads it.

DIR = File.expand_path("../fixtures/runtime_compiled", __dir__)
$LOAD_PATH.unshift(DIR)

# Computed, so the loader cannot resolve it and the run time must.
%w[aliased_extend guarded_toplevel].each { |f| require f }

p UsesAliasedExtend.collected
p GUARDED_WHICH
p guarded_choice
p GuardedHolder.new.which
p UsesAliasedExtend.singleton_class.ancestors.include?(AliasedExtend)
p UsesAliasedExtend.respond_to?(:collect)
p UsesAliasedExtend.method(:collect).owner
