# Class#=== — case-when membership for primitive type names.
# Compile-time decided based on the arg's inferred type.
p Integer === 5
p Integer === 5.0
p Integer === "x"
p Numeric === 5
p Numeric === 5.0
p Comparable === 5
p Float === 5.0
p Float === 5
p String === "hi"
p String === :hi
p Symbol === :hi
p Symbol === "hi"
p Array === [1, 2, 3]
p Array === "x"
p Range === (1..3)
p Range === 5
p TrueClass === true
p FalseClass === false
p NilClass === nil
p Object === 5
p Object === "x"

# More true/false coverage for the remaining primitive arms.
p Hash === {a: 1}
p Hash === [1, 2, 3]
p Numeric === "5"
p Numeric === :sym
p Comparable === 1.5
p Comparable === [1, 2]
p TrueClass === false
p FalseClass === true
p NilClass === 0
p NilClass === false

# Kernel and BasicObject — Ruby's universal ancestors. Every receiver
# is in the Object hierarchy, so `=== anything` is true.
p Kernel === 5
p Kernel === "x"
p Kernel === nil
p BasicObject === 5
p BasicObject === [1]
