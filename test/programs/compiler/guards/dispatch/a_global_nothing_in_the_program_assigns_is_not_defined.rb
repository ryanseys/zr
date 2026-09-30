# `defined?` and its `const_defined?` / `constants.include?` spellings ask
# whether a name is bound YET. A definition further down the program has not
# run, so at the guard the answer is no -- which is exactly what the
# define-it-if-nobody-else-did idiom is written for.

# A global nothing in the program assigns is not defined -- lockfile opens
# with exactly this pair, and stamps the global on its last line. That stamp
# is INSIDE the branch the guard controls, so at the guard it has not run:
# same moment rule the constants above follow.
unless(defined?($__lockfile__) or defined?(Lockfile))
  class Lockfile
    def tag = "lock"
  end
  $__lockfile__ = __FILE__
end
p Lockfile.new.tag
p $__lockfile__.nil?

