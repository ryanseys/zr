# `using` in an eval with the top-level binding refines the code that
# runs after it there, and later evals with that binding. zr fixes each
# send's refinements when it compiles the send, so neither sees it.
module M
  refine String do
    def upcase
      reverse
    end
  end
end
puts "hello world".upcase
b = binding
puts eval(%{using M; "hello world".upcase}, b)
puts eval(%{"hello world".upcase}, b)
puts "hello world".upcase
c = binding
puts eval(%{"hello world".upcase}, c)
