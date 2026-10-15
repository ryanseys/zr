# String#capitalize returns an empty receiver itself, frozen or not,
# after it checks its options; the other case methods, and capitalize of
# any other String, return a new String.
empty = +""
same = empty.capitalize
p same.equal?(empty)
same << "x"
p empty
frozen = "".freeze
p frozen.capitalize.equal?(frozen), frozen.capitalize.frozen?
p "".capitalize(:ascii).equal?("".freeze)
blank = +""
p blank.capitalize(:turkic).equal?(blank)
%i[upcase downcase swapcase].each { |m| p [m, blank.public_send(m).equal?(blank)] }
word = +"ab"
p word.capitalize.equal?(word), word.capitalize
begin
  (+"").capitalize(:nope)
rescue ArgumentError => e
  p e.message
end
begin
  (+"").capitalize(:ascii, :turkic)
rescue ArgumentError => e
  p e.message
end
class Sub < String; end
sub = Sub.new
p sub.capitalize.class, sub.capitalize.equal?(sub)
