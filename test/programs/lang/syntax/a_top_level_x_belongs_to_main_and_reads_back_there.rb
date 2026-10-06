# Expression shapes: multi-value return/break/next, parenthesized
# statement sequences, the fuller interpolation forms, and top-level
# instance variables.

# --- top-level instance variables -------------------------------------------
# At the top level `self` is `main`, an ordinary object -- so `@x` there is
# just its instance variable. A top-level `def` is a private method OF that
# same object, so it sees the same storage.
@config = "set at top level"
p @config
p @never_assigned          # nil, not an error

def read_config
  @config
end
p read_config

def bump
  @count = (@count || 0) + 1
end
bump
bump
bump
p @count
