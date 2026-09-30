# A String-returning method unresolved on a value of unknown type, used as a
# String#+ operand, raises NoMethodError at run time, not a compile error.
class Note
  def initialize(t); @created_at = t; end
  def created_at; @created_at; end
end
def show(note)
  "at " + note.created_at.strftime("%Y")
end
begin
  show(Note.new(nil))
  p :no_raise
rescue NoMethodError
  p :raised
end
# the ordinary path still works
p("a" + "b")
