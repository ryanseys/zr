# Hash conformance
p({}.nil?)                          # object query on empty hash literal
p({}.frozen?)
p({}.empty?)
p({}.is_a?(Hash))
p({}.is_a?(Array))
p(Hash[])                           # Hash[] with no arguments
p({ a: 1, b: 2 }.map { |k, v| nil })       # all-nil block map
p({ a: 1, b: 2 }.collect { |k, v| nil })
p({ a: 1, b: 2 }.map { |k, v| k })
