# Array#collect is an alias of Array#map, so their Method objects are
# equal and hash alike. zr defines the core aliases as separate entries.
p Array.instance_method(:map) == Array.instance_method(:collect)
p Array.instance_method(:map).hash == Array.instance_method(:collect).hash
