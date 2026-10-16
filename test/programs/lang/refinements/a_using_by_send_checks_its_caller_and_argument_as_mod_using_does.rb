module RU
  refine(Integer) { def rr = :refined }
end

def t(label)
  print label, ": "
  p yield
rescue Exception => e
  puts "#{e.class}: #{e.message}"
end

# The frame that calls `using`: a method, or a block in one, is refused
# first; then a self other than the receiver.
t("block at the top") { Module.new.send(:using, RU) }
def in_method = Module.new.send(:using, RU)
t("method") { in_method }
def in_method_block = [1].map { Module.new.send(:using, RU) }
t("block in a method") { in_method_block }
t("__send__ of a class") { Class.new.__send__(:using, RU) }

# Called on self, the argument must be a module, a class not included.
t("a class") { Module.new { send(:using, Class.new) } }
t("an integer") { Module.new { send(:using, 1) } }
t("nil") { Module.new { send(:using, nil) } }
t("a class with a block") { Module.new { send(:using, String) { :ignored } } }
t("in a method on self") { Module.new { def self.go = send(:using, RU) }.go }

# The refinement is not active where `using` failed.
t("not refined") { 1.respond_to?(:rr) }
