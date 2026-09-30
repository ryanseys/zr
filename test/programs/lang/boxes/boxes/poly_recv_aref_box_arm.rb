# A user `def [](k)` that callers call with keys of different types
# (String and Symbol), on receivers of different classes.
#
# The shape comes from Roundhouse's view helper:
# `def field_for(model, field); model[field]; end` where model can be
# an Article, a Comment, a HWIA or a Parameters, and field is a Symbol.

class A
  def [](k)
    "from-A"
  end
end

class B
  def [](k)
    "from-B"
  end
end

# Two callers with different key types.
def lookup_str(receiver, key)
  receiver[key]
end
puts lookup_str(A.new, "alpha")
puts lookup_str(B.new, "beta")

def lookup_sym(receiver, key)
  receiver[key]
end
puts lookup_sym(A.new, :alpha)
puts lookup_sym(B.new, :beta)
