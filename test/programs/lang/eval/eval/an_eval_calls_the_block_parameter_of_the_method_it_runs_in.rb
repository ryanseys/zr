def once(&b) = eval("b.call(2)")
p once { _1 * 21 }

def twice(&b)
  eval("b.call(1) + b.(2)")
end
p twice { _1 * 10 }
