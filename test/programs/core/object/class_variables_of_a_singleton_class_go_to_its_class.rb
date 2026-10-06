# The class variables of a singleton class of a class come from that
# class, not from modules that extend it, and a class variable that an
# included frozen module holds cannot be set.
def t(name)
  puts "#{name}: #{yield.inspect}"
rescue Exception => e
  puts "#{name}: #{e.class}: #{e.message.gsub(/0x\h+/, "0xADDR")}"
end
module Olympians
  @@rule = "Zeus"
end
mod = Module.new
mod.class_variable_set(:@@foo, 1)
mod.freeze
c = Class.new { include(mod) }
t("set") { c.class_variable_set(:@@foo, 2) }
t("eval set") { c.class_eval("@@foo = 2") }
t("get") { c.class_variable_get(:@@foo) }
c = Class.new
c.extend(Olympians)
t("singleton") { c.singleton_class.class_variables }
t("singleton get") { c.singleton_class.class_variable_get(:@@rule) }
c.class_variable_set(:@@foo, 1)
t("singleton after set") { c.singleton_class.class_variables }
t("singleton get after set") { c.singleton_class.class_variable_get(:@@foo) }
t("subclass singleton") { Class.new(c).singleton_class.class_variables }
o = Object.new
o.extend(Olympians)
t("object singleton") { o.singleton_class.class_variables }
t("object singleton get") { o.singleton_class.class_variable_get(:@@rule) }
