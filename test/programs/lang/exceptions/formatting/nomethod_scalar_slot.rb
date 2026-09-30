# A call to a method that the receiver does not have, in a position that
# expects a scalar value. The call raises NoMethodError at runtime, as in
# CRuby.
class CommentRow
  def created_at; "2020-01-01"; end
end
class StoryRow
  def created_at; "2021-02-02"; end
end
class Wrap
  def initialize(note); @note = note; end
  def render
    s = @note.created_at.strftime("%Y")
    s.to_s
  end
end
begin
  puts Wrap.new(CommentRow.new).render
rescue NoMethodError
  puts "NoMethodError"
end
