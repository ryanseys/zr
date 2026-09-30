# A parameter whose only uses are in an if-predicate or an else-branch.
# Those uses must count when the compiler infers the parameter's type
# from the method body.
#
# Body shape:
#   def update(p)
#     if p.title.nil?      # predicate uses p
#       nil
#     else
#       self.title = p.title   # else-branch uses p
#     end
#   end
#
# Two user classes (P, Other) define `title`, so a wrong guess picks the
# wrong class.

class P
  def title
    @title
  end
  def title=(v)
    @title = v
  end
  def body
    @body
  end
  def body=(v)
    @body = v
  end
end

class App
  # `p` is used ONLY inside the if-predicate (`p.title.nil?`),
  # nowhere in the IfNode's body or else-branch.
  def status(p)
    if p.title.nil?
      "no-title"
    else
      "has-title"
    end
  end
end

# IMPORTANT: don't call `App#status` directly — a call site would
# give `p` its type. The test checks that inference from the body
# works without a call site, when two user classes (P, Other)
# define `title`.

class Other
  def title; "wrong"; end
end

# Pin both classes' instances at the top level so they appear in
# the symbol table.
o = Other.new
puts o.title             # wrong

q = P.new
q.title = "hello"
puts q.title             # hello

# `App#status` is defined but never called, so only its body
# gives `p`'s type.
puts "compiled-cleanly"
