# Ruby raises before anything is minted. (It also warns
# `previous definition of TOP was here`, which zr does not track --
# hence the stdout-only check rather than a golden.)

TOP = 1
src = "class TOP; end"
begin
  eval(src)
rescue TypeError => e
  puts e.message
end
