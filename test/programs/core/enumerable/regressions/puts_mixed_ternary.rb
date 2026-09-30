# `puts cond ? :sym : int` prints the value of the arm that runs:
# the Symbol's name, or the Integer. Each arm keeps its own type.

a = 2
puts a%2>0 ? :odd : a    # else: prints "2"

b = 3
puts b%2>0 ? :odd : b    # then: prints "odd"

# Float vs string
c = 1.5
puts c > 0 ? "positive" : c  # then: "positive"
puts c > 5 ? "big" : c       # else: 1.5
