# Hash shorthand with string-valued local variable: `{name:}` takes the
# value of the local `name`, a String.

# Single string-valued shorthand
name = "ada"
who1 = {name:}
puts who1[:name]
puts who1.length

# Mixed string-valued shorthand and explicit string pair
first = "ada"
who2 = {first:, last: "lovelace"}
puts who2[:first]
puts who2[:last]
puts who2.length

# Compare against the explicit equivalent (both should produce the same output)
who3 = {first: first, last: "lovelace"}
puts who3[:first]
puts who3[:last]
puts who3.length

# Three string-valued shorthand keys
a = "alpha"
b = "beta"
c = "gamma"
who4 = {a:, b:, c:}
puts who4[:a]
puts who4[:b]
puts who4[:c]
puts who4.length

# Mixed shorthand and explicit pairs round-tripping a single value type
x = "one"
y = "two"
who5 = {x:, y:, z: "three"}
puts who5[:x]
puts who5[:y]
puts who5[:z]
puts who5.length

# Has-key membership over the inferred hash type
puts who1.has_key?(:name)
puts who2.has_key?(:first)
puts who2.has_key?(:missing)
