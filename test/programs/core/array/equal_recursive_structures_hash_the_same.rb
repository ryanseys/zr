# Equal recursive Arrays and Hashes hash the same, as the outermost hash
# call answers once it meets an object it is inside of, and a hash value
# that is not an Integer is reduced with to_int.
rec = []; rec << rec
p rec.hash == [rec].hash, rec.hash == [[rec]].hash
h = {}; r2 = [h]; h[:x] = r2
p r2.hash == [h].hash, r2.hash == [{x: r2}].hash
x = Object.new; def x.hash = 1.5
p [x].hash == [x].hash
y = Object.new; def y.hash = Object.new.tap { def _1.to_int = 0 }
p [y, y].hash == [y, y].hash
p [1, [2, 3]].hash == [1, [2, 3]].hash, {a: [1]}.hash == {a: [1]}.hash, [1, [2]].hash != [1, [3]].hash
z = Object.new; def z.hash = "no"
p(([z].hash rescue $!.class))
