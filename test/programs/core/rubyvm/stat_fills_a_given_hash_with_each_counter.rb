# RubyVM.stat with a Hash sets each counter in it and returns that Hash.
h = { mine: 1 }
r = RubyVM.stat(h)
p r.equal?(h)
p h.keys.sort
p RubyVM.stat.keys.sort == (h.keys - [:mine]).sort
p RubyVM.stat(:global_cvar_state).is_a?(Integer)
begin
  RubyVM.stat("x")
rescue TypeError => e
  p e.message
end
