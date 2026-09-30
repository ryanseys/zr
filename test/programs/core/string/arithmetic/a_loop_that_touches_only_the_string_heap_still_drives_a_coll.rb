# A `String#+` loop allocates only strings, and no other objects. String
# allocation alone must start a collection, so memory does not grow without
# bound.
#
# Assert that a collection actually fires here: GC.stat["cycle"] counts
# collections. If none runs, this prints "NO COLLECTION"; otherwise it
# prints "collected".

before = GC.stat["cycle"]
s = ""
i = 0
while i < 50000
  s = s + "x"          # fresh result string each step; old s becomes garbage
  s = "" if s.length > 1000   # keep the live set tiny -- all the churn is collectable
  i += 1
end
after = GC.stat["cycle"]
puts(after > before ? "collected" : "NO COLLECTION")
