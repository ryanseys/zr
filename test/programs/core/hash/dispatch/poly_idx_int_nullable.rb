# A receiver whose type is known only at run time, indexed by an Integer-or-nil
# value (from an Integer => Integer hash lookup), answers the element.

h = { 0 => 2, 1 => 3 }   # #[] returns Integer or nil
k = h[0]                  # 2

# A mixed literal makes `box` a mixed Array; its element can be of any type.
box = [[10, 20, 30, 40, 50], "tail"]
tbl = box[0]              # an Array of Integers at run time

p tbl[k]                  # [] with an Integer-or-nil index -> want 30
