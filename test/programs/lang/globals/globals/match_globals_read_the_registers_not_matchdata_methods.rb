"ab" =~ /(a)(b)/
p $~.respond_to?(:last_group), $~.respond_to?(:last_group, true)
p $+, $&, $`, $', $1, $2, $3

"b" =~ /(a)?b/
p $+, $1
"a" =~ /(a)|(b)/
p $+, $1, $2
"xyz" =~ /q/
p $+, $&, $`, $', $1

"héllo wörld" =~ /(ö)/
p $`, $', $&, $+, $`.encoding

class MatchData
  def pre_match = "PRE"
  def post_match = "POST"
  def [](i) = "IDX"
  def captures = ["CAP"]
  def to_a = ["ARR"]
  def size = 99
end
"xaby" =~ /(a)(b)/
p $`, $', $&, $+, $1, $2
p "xaby".sub(/(a)(b)/, '<\+|\0|\1|\2|\`|\'>')
p "xaby".gsub(/(a)(b)/, '[\&]')

