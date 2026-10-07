# The main thread recurses as deep as RUBY_THREAD_VM_STACK_SIZE allows:
# a smaller VM stack gives less depth, a larger one more. A value under
# the least size counts as the least.
def depth(size)
  env = size ? { "RUBY_THREAD_VM_STACK_SIZE" => size.to_s } : {}
  script = "def rec(n) = rec(n + 1) rescue n; begin; rec(0); rescue SystemStackError; end; d = 0; " \
           "begin; (f = ->(n) { d = n; f.(n + 1) }).(0); rescue SystemStackError; end; print d"
  IO.popen([env, RbConfig.ruby, "-e", script], &:read).to_i
end

base = depth(nil)
p depth(0) < base
p depth(10 * 1024 * 1024) > base
p depth("junk") == depth(0)
