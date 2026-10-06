# A core alias such as Array#collect for Array#map gives a Method equal to
# the original's, with the same hash. Two separate methods do not.
p Array.instance_method(:map) == Array.instance_method(:collect)
p Array.instance_method(:map).hash == Array.instance_method(:collect).hash
p [1].method(:map) == [1].method(:collect)
p Hash.instance_method(:select) == Hash.instance_method(:filter)
p String.instance_method(:size) == String.instance_method(:length)
p Array.instance_method(:map) == Array.instance_method(:each)
p [1].method(:map) == [2].method(:collect)
