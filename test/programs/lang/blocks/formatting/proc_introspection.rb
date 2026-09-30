# Proc#arity, #lambda?, and #parameters.

p = Proc.new { |a, b| }
puts p.arity
puts p.lambda?
puts p.parameters.inspect

l = lambda { |a, b| }
puts l.arity
puts l.lambda?
puts l.parameters.inspect
