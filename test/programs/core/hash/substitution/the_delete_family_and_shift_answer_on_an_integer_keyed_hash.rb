# Integer-keyed Hash delete-family + Hash#shift
p({ 1 => "a", 2 => "b" }.delete(1))         # delete
p({ 1 => 10, 2 => 20 }.delete(2))
p({ 1 => 10, 2 => 20 }.slice(1))            # slice
p({ 1 => 10, 2 => 20 }.except(1))           # except
p({ 1 => "a", 2 => "b" }.slice(2))
h = { a: 1, b: 2 }
p h.shift                                    # shift
p h
p({ 1 => 10, 2 => 20 }.shift)
p({}.shift) rescue p(:empty_ok)
h2 = { 1 => 10, 2 => 20 }
h2.delete_if { |_k, v| v > 15 }              # delete-family mutator
p h2
p({ 1 => 10 }.value?(10))                    # value?
p({ 1 => 10 }.has_value?(99))
