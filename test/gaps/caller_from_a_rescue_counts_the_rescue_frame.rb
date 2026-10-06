# In a rescue clause, caller level 1 is the method itself at its def
# line, as CRuby counts the rescue's own frame. zr has no frame for the
# rescue, so level 1 is the caller.
def m
  raise
rescue
  caller_locations(1, 1)[0].lineno
end
p m
