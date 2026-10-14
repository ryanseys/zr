# Coverage.start(eval: true) counts the lines and branches of code that
# eval compiles. A program built with ZR_EVAL=walk (or for wasm32-wasi)
# walks eval code in place of compiling it. The walker ignores the
# counters, as it ignores TracePoint's events, so zr gives the eval's
# value but reports no lines or branches for it (nil).
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
