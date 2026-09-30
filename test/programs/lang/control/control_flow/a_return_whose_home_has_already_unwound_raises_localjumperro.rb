# A `return` whose home has already unwound is a LocalJumpError, not a jump
# into a dead frame.
def escapee = proc { return :gone }
begin
  escapee.call
rescue LocalJumpError => e
  p [:local_jump, e.reason]
end

