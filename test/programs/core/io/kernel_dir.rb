# Kernel#__dir__ returns the dirname of the source file, also when
# the source does not reference __FILE__.
puts __dir__.is_a?(String)
puts __dir__.length > 0
