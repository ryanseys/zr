# Coverage.start(eval: true) counts the lines and branches of code that
# eval runs. A program built with ZR_EVAL=walk (as for wasm32-wasi) walks
# eval code in place of compiling it, and the walk counts them too.
require "coverage"

Coverage.start(lines: true, branches: true, eval: true)
value = eval(<<~CODE, binding, "walked.rb", 1)
  x = Coverage.running? ? 2 : 0
  if x > 1
    :big
  else
    :small
  end
CODE
result = Coverage.result
p value
p result["walked.rb"]
