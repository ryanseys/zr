# String#partition and #rpartition return a String separator that
# matches as the middle element itself; the other pieces, and the empty
# ones when nothing matches, are new Strings.
s = +"a-b-c"
sep = +"-"
parts = s.partition(sep)
p parts, parts[1].equal?(sep), parts[0].equal?(s), parts[2].frozen?
rparts = s.rpartition(sep)
p rparts, rparts[1].equal?(sep)

none = s.partition(+"=")
p none, none[0].equal?(s), none.map(&:frozen?)
rnone = s.rpartition(+"=")
p rnone, rnone[2].equal?(s)

empty = +""
p "ab".partition(empty)[1].equal?(empty), "ab".rpartition(empty)[1].equal?(empty)

frozen = "-".freeze
p s.partition(frozen)[1].equal?(frozen), s.partition(frozen)[1].frozen?

class Dash
  def to_str = "-"
end
p s.partition(Dash.new), s.partition(Dash.new)[1].frozen?

matched = s.partition(/-/)
p matched, matched[1].frozen?, $~[0]

parts[1] << "?"
p sep, s
