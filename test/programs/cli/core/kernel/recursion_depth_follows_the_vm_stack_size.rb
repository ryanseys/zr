# A thread's recursion goes as deep as RUBY_THREAD_VM_STACK_SIZE allows.
# zr runs the main thread on the machine stack that the system gives it,
# so the variable does not change how deep a program may recurse.
def depth(size)
  env = size ? { "RUBY_THREAD_VM_STACK_SIZE" => size.to_s } : {}
  script = "def rec(n) = rec(n + 1) rescue n; begin; rec(0); rescue SystemStackError; end; d = 0; " \
           "begin; (f = ->(n) { d = n; f.(n + 1) }).(0); rescue SystemStackError; end; print d"
  IO.popen([env, RbConfig.ruby, "-e", script], &:read).to_i
end

base = depth(nil)
p depth(0) < base
p depth(10 * 1024 * 1024) > base
