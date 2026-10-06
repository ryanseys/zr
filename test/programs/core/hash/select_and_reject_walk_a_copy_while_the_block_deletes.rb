h = {a: 1, b: 2, c: 3}
p h.select { h.delete(:c); true }, h
h = {a: 1, b: 2, c: 3}
p h.reject { |k, v| h.delete(:c); v == 1 }
