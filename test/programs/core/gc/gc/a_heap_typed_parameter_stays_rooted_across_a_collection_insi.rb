# A method parameter that holds a String stays alive across a collection
# that the method causes, so a later read of it (as in an interpolation)
# gives the String.
def gc_then
  GC.start
  i = 0
  s = ""
  while i < 6000
    s = s + i.to_s + ","
    i += 1
  end
  "G"
end

def wrap(body)
  "#{gc_then}-#{body}"
end

wrap(42)                  # int call site: `body` can also be an Integer
puts wrap("P_" + 7.to_s)  # string call site
