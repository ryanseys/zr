# `&obj` converts with to_proc as rb_check_funcall calls it: a
# method_missing answers when obj has no to_proc, and a to_proc that
# gives no Proc is a TypeError.
class Missing
  def method_missing(*) = proc { "method_missing" }
  def call = [1].map(&self)
end
p Missing.new.call
class NotProc
  def to_proc = 1
  def call = [1].map(&self)
end
begin
  NotProc.new.call
rescue TypeError => e
  p e.message
end
begin
  [1].map(&Object.new)
rescue TypeError => e
  p e.message
end
