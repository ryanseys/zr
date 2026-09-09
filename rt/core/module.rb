# Module's comparisons over the ancestor chain, and the hooks a program
# may override, which do nothing here.
class Module
  private def included(base) = nil
  private def extended(base) = nil
  private def prepended(base) = nil
  private def method_added(name) = nil
  private def method_removed(name) = nil
  private def method_undefined(name) = nil
  private def const_added(name) = nil

  # Every argument is checked before any is spliced; then each module,
  # last first, splices itself through `append_features` and hears
  # `included`. Index loops over the kernel's length: the Array
  # iterators are not defined yet when the core's own includes run,
  # and a program may prepend over Array#size itself.
  def include(*modules)
    mixin(modules, :append_features, :included)
  end

  def prepend(*modules)
    mixin(modules, :prepend_features, :prepended)
  end

  def mixin(modules, splice, hook)
    Primitive.attr! :hidden
    n = Primitive.zr_ary_len_m(modules)
    raise ArgumentError, "wrong number of arguments (given 0, expected 1+)" if n == 0

    i = 0
    while i < n
      mod = modules[i]
      raise TypeError, "wrong argument type #{mod.class} (expected Module)" unless mod.is_a?(Module) && !mod.is_a?(Class)

      i += 1
    end
    i = n - 1
    while i >= 0
      modules[i].send(splice, self)
      modules[i].send(hook, self)
      i -= 1
    end
    self
  end
  private :mixin

  def <(other)
    raise TypeError, "compared with non class/module" unless other.is_a?(Module)
    return false if equal?(other)
    return true if ancestors.include?(other)

    other.ancestors.include?(self) ? false : nil
  end

  def <=(other)
    equal?(other) ? true : self < other
  end

  def >(other)
    raise TypeError, "compared with non class/module" unless other.is_a?(Module)
    return false if equal?(other)

    r = other < self
    r.nil? ? nil : r
  end

  def >=(other)
    equal?(other) ? true : self > other
  end

  def <=>(other)
    return 0 if equal?(other)
    return nil unless other.is_a?(Module)

    r = self < other
    return -1 if r
    return 1 if r == false && other < self

    nil
  end
end

class Class
  private def inherited(subclass) = nil
end

class BasicObject
  private def singleton_method_added(name) = nil
  private def singleton_method_removed(name) = nil
  private def singleton_method_undefined(name) = nil
end

module Kernel
  private def initialize_copy(orig)
    raise TypeError, "initialize_copy should take same class object" unless orig.instance_of?(self.class)

    self
  end

  # nil shows every instance variable in `inspect`; an Array names
  # the ones to show.
  private def instance_variables_to_inspect = nil

  private def initialize_dup(orig) = initialize_copy(orig)
  private def initialize_clone(orig, freeze: nil) = initialize_copy(orig)
end

class Module
  # A literal feature is resolved when the program is compiled.
  def autoload(name, feature) = Primitive.zr_unimplemented("autoload with a computed feature")

  # A String name may be a `::` path, a leading `::` starting at Object;
  # each segment after the first is read without Object's constants.
  def const_get(name, inherit = true)
    name = const_name(name)
    return Primitive.zr_mod_const_get_m(self, name, inherit, false) unless name.is_a?(String) && name.include?("::")

    walk_const_path(name) do |scope, segment, later|
      Primitive.zr_mod_const_get_m(scope, segment, inherit, later)
    end
  end

  def const_defined?(name, inherit = true)
    name = const_name(name)
    return Primitive.zr_mod_const_defined_m(self, name, inherit, false) unless name.is_a?(String) && name.include?("::")

    walk_const_path(name) do |scope, segment, later|
      return false unless Primitive.zr_mod_const_defined_m(scope, segment, inherit, later)

      Primitive.zr_mod_const_get_m(scope, segment, inherit, later)
    end
    true
  end

  def const_source_location(name, inherit = true)
    name = const_name(name)
    return Primitive.zr_mod_const_source_location_m(self, name, inherit, false) unless name.is_a?(String) && name.include?("::")

    *scopes, last = name.split("::", -1)
    scope = walk_const_path(name, scopes) do |inner, segment, later|
      Primitive.zr_mod_const_get_m(inner, segment, inherit, later)
    end
    Primitive.zr_mod_const_source_location_m(scope, last, inherit, scopes.any? { |s| !s.empty? })
  end

  # What a constant lookup reaches when nothing holds the name. A
  # program overrides it to make one up.
  def const_missing(name)
    raise NameError.new("uninitialized constant #{self == Object ? name : "#{self}::#{name}"}", name, receiver: self)
  end

  # `instance_method`, refused when the name is not public.
  def public_instance_method(name)
    method = instance_method(name)
    return method if public_method_defined?(name)

    kind = private_method_defined?(name) ? "private" : "protected"
    raise NameError.new("method '#{method.name}' for #{is_a?(Class) ? "class" : "module"} '#{self}' is #{kind}", method.name, receiver: self)
  end

  # Refinements are not written yet, so a module holds none and none
  # is ever in use.
  def refinements = []

  def self.used_modules = []

  def self.used_refinements = []

  private

  # A Symbol, a String, or what to_str makes of the name.
  def const_name(name)
    Primitive.attr! :hidden
    return name if name.is_a?(Symbol) || name.is_a?(String)

    String.try_convert(name) or raise TypeError, "no implicit conversion of #{conversion_name(name)} into String"
  end

  # Each segment of the path `name` resolved by the block from the
  # scope before it, told whether an earlier segment resolved; the last
  # value answers.
  def walk_const_path(name, segments = name.split("::", -1))
    Primitive.attr! :hidden
    scope = self
    seen = 0
    segments.each_with_index do |segment, i|
      if segment.empty?
        raise NameError.new("wrong constant name #{name}", name, receiver: self) unless i.zero?

        scope = Object
      else
        raise TypeError, "#{scope.inspect} does not refer to class/module" unless scope.is_a?(Module)

        scope = yield(scope, segment, seen.positive?)
        seen += 1
      end
    end
    scope
  end
end

module Kernel
  def autoload(name, feature) = Primitive.zr_unimplemented("autoload with a computed feature")
  def autoload?(name, inherit = true) = Object.autoload?(name)
  private :autoload, :autoload?
end
