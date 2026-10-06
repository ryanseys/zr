# BasicObject is instantiable: it gives a blank instance, like Object.new
# does.
o = BasicObject.new
p :created
q = Object.new
p q.class
