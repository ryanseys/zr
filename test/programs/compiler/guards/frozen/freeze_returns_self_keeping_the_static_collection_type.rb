# `.freeze` returns self, so `names` stays a static Array and
# `names[0]` / `names.length` still work. The example uses a local, not
# the `NAMES = [...].freeze` constant idiom, because a constant read
# always takes the generic path.

names = ["a", "b"].freeze
puts names[0]
puts names.length
puts names.frozen?
