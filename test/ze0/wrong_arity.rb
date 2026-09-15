def two(a, b)
  a + b
end
puts two(1, 2)
puts two(1)
__END__
3
#@ stderr
ze0/wrong_arity.rb:1:in 'Object#two': wrong number of arguments (given 1, expected 2) (ArgumentError)

    caller: ze0/wrong_arity.rb:5
    | puts two(1)
           ^^^
    callee: ze0/wrong_arity.rb:1
    | def two(a, b)
          ^^^
	from ze0/wrong_arity.rb:5:in '<main>'
#@ exit 1
