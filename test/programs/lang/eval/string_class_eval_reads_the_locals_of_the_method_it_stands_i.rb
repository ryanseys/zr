# A class_eval, module_eval or instance_eval of a string reads and writes
# the locals of the method it stands in, as eval does; the gem's heredoc
# form names a local the string never assigns.
module M; end

def attach(mod)
  invoker = 42
  mod.module_eval <<-code, __FILE__, __LINE__
    @v = invoker
    def self.v = @v
  code
  mod.v
end

def sums(mod)
  x = 1
  mod.class_eval("x += 1")
  Object.new.instance_eval("x += 10")
  x
end

p attach(M)
p sums(M)
p M.module_eval("[self, __LINE__]", "f.rb", 7)

