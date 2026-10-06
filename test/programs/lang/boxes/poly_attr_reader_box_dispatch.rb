# A setter whose ivar holds values of mixed types receives an attr_reader
# value from another class. The String value arrives unchanged.

class Comment
  attr_accessor :commenter

  def []=(field, value)
    case field
    when :commenter then @commenter = value
    when :other then @other = value
    end
  end
end

class CommentRow
  attr_reader :commenter
  def initialize(c); @commenter = c; end
end

# Comment's @commenter also takes an Integer here.
seed = Comment.new
seed[:other] = 42
seed[:commenter] = "x"

def update_from_row(c, p)
  c.commenter = p.commenter
end

c = Comment.new
row = CommentRow.new("alice")
update_from_row(c, row)
puts c.commenter
