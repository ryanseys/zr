# A method that always raises never returns a value. Its result can still
# sit in value position -- assigned to a local or passed as an argument.
# That use never runs, because the call raises first.

def boom
  raise "always raises"
end

def sink(x)
  x.to_s
end

def use_arg
  sink(boom)        # boom never returns; arg in value position
end

def use_local
  v = boom          # boom never returns; local in value position
  v.to_s
end

# Never executed (CRuby never raises), but all must AOT-compile -- including
# a void value handed straight to puts / print / p.
if false
  use_arg
  use_local
  puts boom
  print boom
  p boom
end
puts "ok"
