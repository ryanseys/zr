# An instance of a copy of String (`String.clone`) runs String's own
# methods as a String does, as test_class.rb's StrClone does, though it is
# no kind of String. A program's own bind of a String method to it still
# raises, as in CRuby.
StrClone = String.clone
s = StrClone.new("ab\ncd")
p s.is_a?(String), s.lines, s.each_line.to_a, s.upcase, s.chars.size, s.sub("a", "x"), s.include?("cd")
class String; def later = :later; end
p s.respond_to?(:later)
require "pp"
pp s
begin
  String.instance_method(:lines).bind_call(s)
rescue TypeError => e
  p e.message
end
