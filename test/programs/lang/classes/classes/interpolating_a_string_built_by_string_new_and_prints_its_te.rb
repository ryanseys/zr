# String interpolation of a method that returns a String built by
# `String.new` + `<<` prints the text of the string. The shape comes from
# the roundhouse view code, which turns `io << x; io << y` runs into
# `io << "...#{y}..."`.

module M
  def self.make
    s = String.new
    s << "hello"
    s
  end
end

puts "[#{M.make}]"
