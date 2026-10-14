# A Symbol's methods read its one frozen name, the String that to_s,
# name and id2name give: not a to_s or a String method that the program
# writes.
s = :héllo
name = s.name
p name, name.frozen?, s.to_s.equal?(name), s.id2name.equal?(name)
p s[0], s[1, 3], s[-1], s[1..], s[/l+/], s[9], s[9, 1], s.slice(0, 2), s["ll"]
p s.length, s.size, s.empty?, :"".empty?, :"".length, :"".size
p s.upcase, s.succ, s.start_with?("hé"), s.end_with?("lo", "x"), s.encoding

[[], [1, 2, 3]].each do |args|
  s[*args]
rescue ArgumentError => e
  p e.message
end

class Symbol
  def to_s = "other"
end
p s.length, s[0], s.upcase, s.inspect, s.name, s.empty?

class String
  def length = 99
  def empty? = true
end
p s.length, s.size, s.empty?, :"".empty?
