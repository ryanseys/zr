# `case <string> when :sym_literal` (and the symmetric
# `case <symbol> when "string_literal"`): `:sym === "string"` is false
# (Symbol#=== only matches Symbols), and `"string" === :sym` is also
# false. The case falls through to the else clause, as in CRuby.

def lookup(name)
  case name
  when :id
    1
  when :body
    2
  else
    -1
  end
end

# String case-expr against symbol when-arms — every arm misses,
# else clause runs.
puts lookup("id")     # -1 (not 1)
puts lookup("body")   # -1 (not 2)
puts lookup("nope")   # -1

def reverse(sym)
  case sym
  when "id"
    1
  when "body"
    2
  else
    -1
  end
end

# Symbol case-expr against string when-arms — symmetric: every
# arm misses, else runs.
puts reverse(:id)     # -1
puts reverse(:body)   # -1

# Sanity: matching arms still work.
def lookup_sym(s)
  case s
  when :id
    1
  when :body
    2
  else
    -1
  end
end
puts lookup_sym(:id)   # 1
puts lookup_sym(:body) # 2
