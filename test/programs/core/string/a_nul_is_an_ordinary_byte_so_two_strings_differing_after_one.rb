# A NUL is an ordinary byte in a Ruby String, and comparison does not stop at
# the first one. Two strings that differ only after a NUL are not equal, so
# they sort apart, stay two in uniq, and are two Hash keys.
s = "a\0b"
t = "a\0c"
p(s == t)
p(s.casecmp(t))
p(s.casecmp?(t))
p([t, s].sort.map(&:bytes))
p([s, t].max.bytes)
p([s, t].min.bytes)
p([s, t].uniq.size)
p([s, t].count(t))
p([s, t].index(t))
p([s, t].include?(t))
p(([s, t] - [s]).map(&:bytes))
p(([s, t] & [t]).map(&:bytes))
p(([s] | [t]).map(&:bytes))
p([s, t].group_by { |x| x }.size)
p({ s => 1, t => 2 }.size)
# The comparison operators also read past the NUL: `<=>` is not 0, and the
# relational four order by the bytes after the shared prefix.
p(s <=> t)
p(s < t)
p(s > t)
p(s <= t)
p(s >= t)
p(s.between?("a\0a", "a\0d"))
p(s.clamp("a\0c", "a\0d").bytes)
p((s.."a\0d").include?(t))
u = "a" + 0.chr + "b"
p(u <=> "a\0c")
p(u < "a\0c")
case t
when s.."a\0d" then puts "in"
else puts "out"
end
