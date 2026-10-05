# A NameError for a class variable names it and its class. backtrace
# returns one Array, which a dup shares. A report of an exception with no
# detailed_message shows the class name.
class CvR
  def go = @@nope
end
begin
  CvR.new.go
rescue NameError => e
  p e.name, e.receiver
end

begin
  raise "x"
rescue => e
  e.backtrace.unshift "first"
  p e.backtrace[0], e.dup.backtrace.equal?(e.backtrace)
  e.set_backtrace(["hi"])
  p e.backtrace
end

e = RuntimeError.new("new error")
class << e
  undef :detailed_message
end
puts e.full_message(highlight: false).lines.first.sub(/^.*?: /, "")
puts e.full_message(highlight: true).lines.first.sub(/^.*?: /, "").inspect
puts RuntimeError.new("").full_message(highlight: false).lines.first.sub(/^.*?: /, "")
