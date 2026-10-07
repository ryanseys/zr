# Module#const_get, #const_defined? and #const_source_location call no
# method of the module, as ruby's C does: a module that answers
# `const_name` or `walk_const_path` (the config gem's readers, made with
# define_method) keeps them for its own callers.
class Configuration < Module
  def initialize(**attributes)
    attributes.each do |name, default|
      define_method(name) { default }
    end
  end
end

module Conf
  extend Configuration.new(const_name: "Settings", walk_const_path: :walked)
  Inner = Module.new
  Inner.const_set(:DEEP, 1)
end

p Conf.const_name, Conf.walk_const_path
p Conf.const_defined?(:VERSION, false), Conf.const_defined?("Inner::DEEP")
p Conf.const_get(:Inner) == Conf::Inner, Conf.const_get("Inner::DEEP")
p Conf.const_source_location("Inner::DEEP").class
p((Conf.const_get("Inner::NOPE") rescue $!.class))
