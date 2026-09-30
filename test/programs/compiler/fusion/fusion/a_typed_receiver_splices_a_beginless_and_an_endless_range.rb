# Array#[]= splice exceptional cases: exact CRuby exception class + message.

# typed receivers handle beginless / endless range splices
b = [1, 2, 3]
b[..1] = [9]
p b
b = [1, 2, 3]
b[1..] = [8]
p b
