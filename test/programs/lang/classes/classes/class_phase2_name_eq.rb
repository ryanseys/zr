# `.name`, `.inspect`, `.==`, `.!=`, `.eql?` on a Class value:
#
#   - `.name` / `.inspect` give the bare class name, like `.to_s`.
#   - `.==` / `.eql?` compare the class, and `.!=` is the negation.
#
# Coverage:
#   - .name / .inspect on a class literal and through obj.class.
#   - == / != / eql? between class literals, mixing with subclass,
#     and through obj.class chains.
#   - .class on a subclass instance gives the subclass.

class Row
  attr_accessor :id
  def initialize
    @id = 0
  end
end

class Article < Row
end

# Direct class literal.
puts Row.name                 # Row
puts Article.inspect          # Article

# Through obj.class.
r = Row.new
a = Article.new
puts r.class.name             # Row
puts a.class.inspect          # Article

# Equality / inequality / eql?
puts (Row == Row).to_s        # true
puts (Row == Article).to_s    # false
puts (Row != Article).to_s    # true
puts (Row != Row).to_s        # false
puts Row.eql?(Row).to_s       # true
puts Row.eql?(Article).to_s   # false

# Through obj.class chains.
puts (r.class == Row).to_s            # true
puts (r.class == Article).to_s        # false
puts (a.class != Row).to_s            # true
puts (a.class == Article).to_s        # true
puts r.class.eql?(Row).to_s           # true
