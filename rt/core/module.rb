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
      raise TypeError, "wrong argument type #{conversion_name(mod)} (expected Module)" unless mod.is_a?(Module) && !mod.is_a?(Class)

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
  # CRuby names BasicObject inside itself too, so a class that inherits
  # from it alone still reaches the name.
  BasicObject = ::BasicObject

  private def singleton_method_added(name) = nil
  private def singleton_method_removed(name) = nil
  private def singleton_method_undefined(name) = nil
end

module Kernel
  # rb_obj_init_copy: a copy of itself is nothing to do, a frozen
  # receiver takes no copy, and the copy has to be of the same class.
  private def initialize_copy(orig)
    return self if equal?(orig)

    Primitive.zr_frozen_error(self) if frozen?
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
  # A module's clone is its own row, as ruby keeps it.
  private def initialize_clone(orig, freeze: nil) = super
end

class Module
  # A literal feature is resolved when the program is compiled; a
  # computed one is required when the constant is first read.
  def autoload(name, feature)
    path = File.path(feature)
    Primitive.zr_autoload_computed(self, autoload_name(name), path, nil,
                                   Kernel.loaded_feature?(path), Kernel.feature_file(path))
  end

  # A constant name as rb_to_id takes one: a Symbol, or a String or what
  # `to_str` answers.
  def autoload_name(name)
    Primitive.attr! :hidden
    return name if name.is_a?(Symbol) || name.is_a?(String)

    String.try_convert(name) or raise TypeError, "#{name.inspect} is not a symbol nor a string"
  end
  private :autoload_name

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

  # `refine C do ... end`: the methods go in a holder module, never on
  # C itself, so they stay invisible until a `using` names this module.
  def refine(target, &block)
    raise ArgumentError, "no block given" unless block
    raise TypeError, "wrong argument type #{conversion_name(target)} (expected Class or Module)" unless target.is_a?(Module)

    table = (@__refinements__ ||= {})
    holder = table[target]
    unless holder
      holder = Primitive.zr_refinement_new(target, @__activated__ ||= [])
      holder.instance_variable_set(:@__origin__, self)
      table[target] = holder
    end
    Primitive.zr_refine_body(block, holder)
    holder
  end

  private :refine

  def refinements = @__refinements__ ? @__refinements__.values : []

  # `using` does its work where it is written, which the compiler sees;
  # anywhere else it is the refusal.
  def using(mod)
    raise RuntimeError, "Module#using is not permitted in methods"
  end
  private :using

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
  # On the class the call stands in, as rb_f_autoload registers.
  def autoload(name, feature)
    path = File.path(feature)
    Primitive.zr_autoload_computed(Kernel, Module.instance_method(:autoload_name).bind_call(Kernel, name), path,
                                   Primitive.zr_eval_cref, Kernel.loaded_feature?(path), Kernel.feature_file(path))
  end
  def autoload?(name, inherit = true) = Object.autoload?(name)
  private :autoload, :autoload?
end

# The holder `Module#refine` makes. It has no name of its own; the pair
# it stands for is what it shows.
class Refinement
  def target = Primitive.zr_refined_class(self)

  # A module's OWN methods copied in at the visibility they were
  # declared with. Ruby copies rather than includes, so what the module
  # inherits stays out.
  def import_methods(*modules)
    modules.each do |mod|
      raise TypeError, "wrong argument type #{conversion_name(mod)} (expected Module)" unless mod.instance_of?(Module)
    end
    modules.each do |mod|
      mod.instance_methods(false).each { |name| define_method(name, mod.instance_method(name)) }
      mod.private_instance_methods(false).each do |name|
        define_method(name, mod.instance_method(name))
        private name
      end
    end
    self
  end
  private :import_methods
end

# main's own, on the toplevel object's singleton class, as CRuby puts it.
class << self
  # Only the compiler activates a refinement, where the source writes
  # the `using`; the method itself is the refusal every other spot gets.
  def using(mod)
    raise RuntimeError, "main.using is permitted only at toplevel"
  end

  private :using
end

# A module is made by Module.new alone: ruby undefines allocate on
# Module's singleton class, and Class.allocate is Class's own again.
class << Module
  undef_method :allocate
end
