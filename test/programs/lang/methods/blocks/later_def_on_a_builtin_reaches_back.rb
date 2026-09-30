# A later `def` reopening a BUILTIN class does not reach BACK: a call written
# above the reopen answers with the builtin body.
#
# The reopen is POSITIONAL. It takes effect where the `class Foo ... end`
# stands. This is true for a statically bound site, a dynamic site, and each
# fold. `p [1,2].size` before `class Array; def size` answers the real size.
#
# Above that line, the reopened body forwards to the method it replaced.
#
# Two things the forward is NOT. It is not `super`: `super` resumes PAST the
# reopened class, and a name the builtin owns outright (`Array#size`) has
# nothing above it -- ruby raises "no superclass method" for a `super` written
# there, and rightly. And it is not free of the block: a body that names no
# `&blk` still has to forward the caller's, so a flagged body takes a block
# parameter whether or not it declares one.
#
# `a_reopened_builtin_answers_from_its_own_line.rb` carries the widened sweep.

p [1, 2].take_while { true }
class Array
  def take_while
    :array_own
  end
end
p [1, 2].take_while { true }
