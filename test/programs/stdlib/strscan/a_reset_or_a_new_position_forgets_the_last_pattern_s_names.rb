# CLEAR_MATCH_STATUS forgets the last Regexp with the match, so
# named_captures is empty after reset, terminate, unscan, string= and a
# scan of a String or a byte. A scan that fails keeps its Regexp's names,
# each with nil. fixed_anchor? is true or false, as RTEST reads the
# keyword. An empty rest or peek keeps the string's encoding.
require "strscan"

def names(label, s) = puts "#{label}: #{s.named_captures.inspect} #{s.matched?}"

s = StringScanner.new("test string")
s.scan(/(?<t>\w+)/)
names("after a scan", s)
s.scan(/(?<x>z)/)
names("after a failed scan", s)
s.scan(/(?<t>\w+)/) rescue nil
s.reset
names("after reset", s)
s.scan(/(?<a>\w+)/)
s.terminate
names("after terminate", s)
s.reset
s.scan(/(?<t>\w+)/)
s.unscan
names("after unscan", s)
s.scan(/(?<t>\w+)/)
s.string = "other"
names("after string=", s)
s.scan(/(?<o>o)/)
s.scan("th")
names("after a String scan", s)
s.scan(/(?<e>e)/)
s.getch
names("after getch", s)
s.scan(/(?<r>r)/) || s.reset
s.scan(/(?<o>o)/)
s.get_byte
names("after get_byte", s)
s.reset
s.scan(/(?<o>o)/)
s.scan_byte
names("after scan_byte", s)
s.reset
s.scan(/(?<n>\d+)?/)
p s.scan_integer
names("after scan_integer", s)

p [StringScanner.new("a").fixed_anchor?, StringScanner.new("a", true).fixed_anchor?,
   StringScanner.new("a", fixed_anchor: nil).fixed_anchor?, StringScanner.new("a", fixed_anchor: 1).fixed_anchor?,
   StringScanner.new("a", fixed_anchor: true).fixed_anchor?]

[+"", (+"").b, (+"").force_encoding("EUC-JP"), "ab".b].each do |text|
  t = StringScanner.new(text)
  t.terminate
  p [t.rest.encoding, t.peek(3).encoding, t.rest.frozen?]
end
