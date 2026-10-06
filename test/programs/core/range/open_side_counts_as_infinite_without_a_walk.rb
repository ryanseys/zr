# A range with an open side holds an infinite count, and CRuby answers
# that without a walk. An argument or a block counts the members that
# match, so those walk and a side that cannot iterate raises. A walk
# backwards names the end it cannot start from, which is the begin of a
# beginless range.
def t = yield rescue [$!.class, $!.message]

p t { (..5).count }
p t { (1..).count }
p t { (..5.0).count }
p t { (1..5).count }
p t { ("a".."e").count }
p t { (1.0..5.0).count }
p t { (..5).count(3) }
p t { (1..5).count { |x| x.odd? } }

p t { (..5).reverse_each.first(3) }
p t { (..5.0).reverse_each.first(2) }
p t { (1..).reverse_each.first(2) }
p t { (1.0..5.0).reverse_each.to_a }

