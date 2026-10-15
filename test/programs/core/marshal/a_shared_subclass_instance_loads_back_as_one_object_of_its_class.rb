# A user-class record (`C`) of a String, Array or Hash is linked by the
# slot of its value, which comes before the value's own elements, so a
# second reference (`@`) finds the subclass instance, not an element.
class Page < Array
  attr_accessor :source
end

class Note < String; end

class Table < Hash; end

pg = Page[1, "a"]
pg.source = "room"
both = Marshal.load(Marshal.dump([pg, pg, 2]))
p both[0].class, both[1].class, both[0].equal?(both[1]), both[1].source, both[2]

note = Note.new("hi")
again = Marshal.load(Marshal.dump([note, "x", note]))
p again.map(&:class), again[0].equal?(again[2])

table = Table[a: "one", b: [2]]
tables = Marshal.load(Marshal.dump({ first: table, second: table }))
p tables[:first].class, tables[:first].equal?(tables[:second]), tables[:second]

nested = Page[Page[1], "b"]
outer = Marshal.load(Marshal.dump([nested, nested[0], nested]))
p outer.map(&:class), outer[0].equal?(outer[2]), outer[0][0].equal?(outer[1])

own = Page[1]
own << own
self_ref = Marshal.load(Marshal.dump(own))
p self_ref.class, self_ref[1].equal?(self_ref)

strings = Marshal.load(Marshal.dump([Note.new("a"), Note.new("b"), "c"].then { [*it, it[1]] }))
p strings.map(&:class), strings[1].equal?(strings[3])
