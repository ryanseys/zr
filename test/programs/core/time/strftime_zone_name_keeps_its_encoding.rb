# %Z with a zone object's abbreviation: the result takes the encoding
# that it and the name are compatible in, else the name converts to the
# format's encoding with a replacement for what does not convert (ruby
# #22416). A compound directive (%+) carries the same rule.
class TZ
  attr_reader :name
  def initialize(name, abbr, offset) = (@name, @abbr, @offset = name, abbr, offset)
  def local_to_utc(t) = t - @offset
  def utc_to_local(t) = t + @offset
  def abbr(t) = @abbr
end
def show(s) = p([s, s.encoding, s.valid_encoding?])
zone = TZ.new("Encoding", "éAAA", 0)
enc = Encoding::ISO_8859_1
show Time.new(2020, 1, 1, 0, 0, 0, zone).strftime("A%Z".encode(enc))
show Time.new(2020, 1, 1, 0, 0, 0, zone).strftime("\u0080%Z".encode(enc))
show Time.new(2020, 1, 1, 0, 0, 0, zone).strftime("%Z")
show Time.new(2020, 1, 1, 0, 0, 0, zone).strftime("%Z".b)
show Time.new(2020, 1, 1, 0, 0, 0, zone).strftime("%Z".encode("US-ASCII"))
z2 = TZ.new("Encoding", "\u{6771 4eac 6a19 6e96 6642}".encode(Encoding::SJIS), 0)
show Time.new(2020, 1, 1, 0, 0, 0, z2).strftime("%Z")
show Time.new(2020, 1, 1, 0, 0, 0, z2).strftime("\u{2606}%Z")
show Time.new(2020, 1, 1, 0, 0, 0, z2).strftime("%Z".encode("EUC-JP"))
z3 = TZ.new("Encoding", "\xff".b, 0)
show Time.new(2020, 1, 1, 0, 0, 0, z3).strftime("x%Z") rescue p $!
show Time.new(2020, 1, 1, 0, 0, 0, z3).strftime("☆%Z") rescue p $!
show Time.new(2020, 1, 1, 0, 0, 0, zone).strftime("%+")
show Time.new(2020, 1, 1, 0, 0, 0, zone).strftime("%^Z|%#Z|%10Z|%-Z")
show Time.new(2020, 1, 1, 0, 0, 0, TZ.new("A", "EST", 0)).strftime("é %Z".encode("ISO-8859-1"))
show Time.new(2020, 1, 1, 0, 0, 0, "+09:00").strftime("%Z|")
show Time.utc(2020).strftime("%Zé")
