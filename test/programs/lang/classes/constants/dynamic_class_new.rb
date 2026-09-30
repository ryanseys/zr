# Dynamic `klass.new`, where `klass` is a Class value and not a constant.
# The delegated_type / STI shape needs this, because data picks the class.
#
# Coverage:
#   - A method gets a class as a parameter, calls .new, and the
#     instance answers its own class's methods.
#   - Three classes go through the same call site.
#   - A Class held in a local variable works the same way.

class Article
  def kind; "article"; end
end

class Page
  def kind; "page"; end
end

class Comment
  def kind; "comment"; end
end

def make(klass)
  klass.new
end

a = make(Article)
p = make(Page)
c = make(Comment)

puts a.kind
puts p.kind
puts c.kind

# Single dispatch via a Class-typed local variable.
k = Article
obj = k.new
puts obj.kind
