# The strings the core library builds from plain ASCII -- a number's
# digits, nil's and true's names, an empty collection's inspect -- are
# US-ASCII, not UTF-8, as rb_usascii_str_new makes them; a symbol's name
# is US-ASCII when it is plain ASCII; the plain object form is binary.
# Which encoding a string holds decides what joining it answers.
rows = {
  "nil.to_s" => nil.to_s, "true.to_s" => true.to_s, "false.inspect" => false.inspect,
  "1.to_s" => 1.to_s, "(2**70).to_s" => (2**70).to_s, "1.5.to_s" => 1.5.to_s, "1.0.inspect" => 1.0.inspect,
  "1r.to_s" => 1r.to_s, "1i.inspect" => 1i.inspect, ":a.to_s" => :a.to_s, ":a.inspect" => :a.inspect,
  "nil.inspect" => nil.inspect, "[].inspect" => [].inspect, "[1].inspect" => [1].inspect, "{}.to_s" => {}.to_s,
  "(1..2).inspect" => (1..2).inspect, "Object.new.to_s" => Object.new.to_s, "Time.at(0).utc.to_s" => Time.at(0).utc.to_s,
  "3.chr" => 3.chr, "65.chr" => 65.chr, "255.chr" => 255.chr, "1.digits.inspect" => 1.digits.inspect,
  "12.to_s(2)" => 12.to_s(2), "format('%d', 1)" => format("%d", 1), "'%s' % 'a'" => "%s" % "a",
  "[1].join" => [1].join, "[].join" => [].join, "Integer.name" => Integer.name, "Comparable.to_s" => Comparable.to_s
}
rows.each { |label, value| puts "#{label}\t#{value.encoding}" }
x = "a".b
puts "joined\t#{"#{nil}#{x}".encoding} #{"#{1}#{x}".encoding} #{(1.to_s + "é").encoding} #{(+nil.to_s << "é".b).encoding}"

__END__
nil.to_s	US-ASCII
true.to_s	US-ASCII
false.inspect	US-ASCII
1.to_s	US-ASCII
(2**70).to_s	US-ASCII
1.5.to_s	US-ASCII
1.0.inspect	US-ASCII
1r.to_s	US-ASCII
1i.inspect	US-ASCII
:a.to_s	US-ASCII
:a.inspect	US-ASCII
nil.inspect	US-ASCII
[].inspect	US-ASCII
[1].inspect	US-ASCII
{}.to_s	US-ASCII
(1..2).inspect	US-ASCII
Object.new.to_s	ASCII-8BIT
Time.at(0).utc.to_s	US-ASCII
3.chr	US-ASCII
65.chr	US-ASCII
255.chr	ASCII-8BIT
1.digits.inspect	US-ASCII
12.to_s(2)	US-ASCII
format('%d', 1)	UTF-8
'%s' % 'a'	UTF-8
[1].join	US-ASCII
[].join	US-ASCII
Integer.name	US-ASCII
Comparable.to_s	US-ASCII
joined	ASCII-8BIT ASCII-8BIT UTF-8 ASCII-8BIT
