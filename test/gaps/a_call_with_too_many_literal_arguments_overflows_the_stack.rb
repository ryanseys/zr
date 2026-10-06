# CRuby pushes the literal arguments of a call on its VM stack, so a
# call with 140,000 of them raises SystemStackError before the method
# runs (test_exception.rb, test_too_many_args_in_eval). zr has room for
# them, and `raise` refuses the count with an ArgumentError.
arg_string = (0...140_000).to_a.join(", ")
begin
  eval "raise(#{arg_string})"
rescue SystemStackError, ArgumentError => e
  p e.class
end
