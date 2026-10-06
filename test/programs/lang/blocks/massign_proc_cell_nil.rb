# Multi-assign of nil into a captured Proc variable sets it to nil, and the
# closure that captured it then sees nil.
def make
  p = proc { "orig" }
  esc = lambda { p ? p.call : "was nil" }   # captures p -> heap cell
  p, n = nil, 5                             # nil into the captured proc cell
  puts n
  esc
end
e = make
puts e.call
