# A class/module class method whose name is also a Kernel/Object
# method (`hash`, `inspect`, `methods`, ...) keeps its user-defined
# return type. `def self.hash(plain)` that returns a String answers
# a String, not the Integer of Kernel#hash.
#
# Coverage:
#   - class method named `hash` on a class in a module, returning String,
#   - class method named `methods` returning String,
#   - class method named `inspect_kind` returning String.

module Auth
  class Password
    def self.hash(plain)
      "pbkdf2$" + plain
    end
  end
end

stored = Auth::Password.hash("hunter2")
puts stored                               # pbkdf2$hunter2
puts stored.length.to_s                   # 14

class Registry
  def self.methods(prefix)
    "[" + prefix + ":methods]"
  end

  def self.inspect_kind(kind)
    "<Registry inspect: " + kind + ">"
  end
end

names = Registry.methods("public")
puts names                                # [public:methods]
puts names.length.to_s                    # 16

shape = Registry.inspect_kind("module")
puts shape                                # <Registry inspect: module>
