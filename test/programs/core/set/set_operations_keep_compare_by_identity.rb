# The sets that Set's operations make compare by identity when the
# receiver does (ruby 4.1): &, ^, classify, divide, collect!/map!,
# flatten and flatten!. The others (|, -, dup) kept the flag already.
a1 = "a"
a2 = +"a"
b = "bb"

ident = Set[a1, b].compare_by_identity
plain = Set[a1, b]

def show(label, set)
  puts "#{label}: #{set.class} #{set.compare_by_identity?} #{set.size}"
end

show("&  set", ident & Set[a1, a2])
show("&  array", ident & [a1, a2])
show("&  plain receiver", plain & Set[a1].compare_by_identity)
show("intersection", ident.intersection([a2]))
# ^ with an Enumerable: its temporary set compares by identity too, so a1
# and a2 each toggle as their own member.
show("^  array", ident ^ [a1, a2])
show("^  set", ident ^ Set[a2])
show("^  plain", plain ^ [a1, a2])
show("|", ident | [a2])
show("-", ident - [a2])
show("flatten", Set[1, Set[a1, a2]].compare_by_identity.flatten)
show("flatten plain", Set[1, Set[a1, a2]].flatten)

s = Set[1, Set[a1, a2]].compare_by_identity
s.flatten!
show("flatten!", s)
s = Set[1, 2].compare_by_identity
p s.flatten!
show("flatten! none", s)

s = Set[a1, b].compare_by_identity
s.map! { |x| x.upcase }
show("map!", s)
s = Set[a1, b].compare_by_identity
s.collect! { |x| x.size }
show("collect!", s)
s = Set[a1, a2]
s.map!(&:upcase)
show("map! plain", s)

ident.classify(&:size).sort_by(&:first).each { |key, set| show("classify #{key}", set) }
plain.classify(&:size).sort_by(&:first).each { |key, set| show("classify plain #{key}", set) }

parts = Set[a1, a2, b].compare_by_identity.divide(&:size)
show("divide", parts)
parts.sort_by(&:size).each { |set| show("divide part", set) }
parts = Set[1, 2, 4, 5, 9].compare_by_identity.divide { |x, y| (x - y).abs == 1 }
show("divide/2", parts)
parts.sort_by { |set| set.min }.each { |set| show("divide/2 part", set) }
parts = Set[1, 2, 4].divide { |x, y| (x - y).abs == 1 }
parts.sort_by { |set| set.min }.each { |set| show("divide/2 plain part", set) }

# A subclass keeps its class and the flag.
class MySet < Set; end
m = MySet[a1, b].compare_by_identity
show("subclass &", m & [a1])
show("subclass ^", m ^ [a2])
show("subclass flatten", MySet[MySet[a1]].compare_by_identity.flatten)
m.classify(&:size).sort_by(&:first).each { |key, set| show("subclass classify #{key}", set) }
show("subclass divide part", m.divide(&:size).first)
m.map!(&:size)
show("subclass map!", m)
