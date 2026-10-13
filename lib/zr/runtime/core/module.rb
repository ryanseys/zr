# frozen_string_literal: true

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
    # rb_mod_include: a refinement mixes in nothing any more.
    raise TypeError, "Refinement##{splice == :append_features ? 'include' : 'prepend'} has been removed" if is_a?(Refinement)
    n = Primitive.zr_ary_len_m(modules)
    raise ArgumentError, +"wrong number of arguments (given 0, expected 1+)" if n == 0

    i = 0
    while i < n
      mod = modules[i]
      raise TypeError, "wrong argument type #{conversion_name(mod)} (expected Module)" unless mod.is_a?(Module) && !mod.is_a?(Class)
      # ensure_includable: a refinement is never spliced into a chain.
      raise TypeError, "Cannot #{splice == :append_features ? 'include' : 'prepend'} refinement" if mod.is_a?(Refinement)

      i += 1
    end
    i = n - 1
    while i >= 0
      # By name, as rb_funcall calls them: a module with a `send` of its
      # own (REXML::Functions) does not intercept the hooks.
      Primitive.zr_funcall_m(modules[i], splice, self)
      Primitive.zr_warn_prepended_operators(self) if splice == :prepend_features
      Primitive.zr_funcall_m(modules[i], hook, self)
      i -= 1
    end
    self
  end
  private :mixin

  def <(other)
    raise TypeError, +"compared with non class/module" unless other.is_a?(Module)
    return false if equal?(other)
    return true if ancestors.include?(other)

    other.ancestors.include?(self) ? false : nil
  end

  def <=(other)
    equal?(other) ? true : self < other
  end

  def >(other)
    raise TypeError, +"compared with non class/module" unless other.is_a?(Module)
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
    raise TypeError, +"initialize_copy should take same class object" unless orig.instance_of?(self.class)

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
    raise ArgumentError, +"empty feature name" if path.empty?
    file = Kernel.feature_file(path)
    Primitive.zr_autoload_computed(self, autoload_name(name), path, nil, Kernel.loaded_feature?(path, file), file)
  end

  # rb_mod_autoload_relative (ruby 4.1): autoload of `feature` taken from
  # the directory of the caller's file (Kernel.relative_feature).
  def autoload_relative(name, feature)
    name = autoload_name(name)
    autoload(name, Kernel.relative_feature(feature))
  end

  # A constant name as rb_to_id takes one: a Symbol, or a String or the
  # value of `to_str`.
  def autoload_name(name)
    Primitive.attr! :hidden
    return name if name.is_a?(Symbol) || name.is_a?(String)

    String.try_convert(name) or raise TypeError, "#{name.inspect} is not a symbol nor a string"
  end
  private :autoload_name

  # rb_define_module_under, as an extension ported to Ruby starts: a
  # constant `name` that holds something other than a module stops it,
  # with the C API's message, before its `module` opens.
  def native_module(name)
    Primitive.attr! :hidden
    return unless const_defined?(name, false)

    value = const_get(name, false)
    raise TypeError, "#{name} is not a module (#{value.class})" unless value.is_a?(Module) && !value.is_a?(Class)
  end
  private :native_module

  # A String name may be a `::` path, a leading `::` starting at Object;
  # each segment after the first is read without Object's constants.
  def const_get(name, inherit = true)
    name = Module.const_name(name)
    return Primitive.zr_mod_const_get_m(self, name, inherit, false) unless name.is_a?(String) && name.include?("::")

    Module.walk_const_path(self, name) do |scope, segment, later|
      Primitive.zr_mod_const_get_m(scope, segment, inherit, later)
    end
  end

  def const_defined?(name, inherit = true)
    name = Module.const_name(name)
    return Primitive.zr_mod_const_defined_m(self, name, inherit, false) unless name.is_a?(String) && name.include?("::")

    Module.walk_const_path(self, name) do |scope, segment, later|
      return false unless Primitive.zr_mod_const_defined_m(scope, segment, inherit, later)

      Primitive.zr_mod_const_get_m(scope, segment, inherit, later)
    end
    true
  end

  def const_source_location(name, inherit = true)
    name = Module.const_name(name)
    return Primitive.zr_mod_const_source_location_m(self, name, inherit, false) unless name.is_a?(String) && name.include?("::")

    *scopes, last = name.split("::", -1)
    scope = Module.walk_const_path(self, name, scopes) do |inner, segment, later|
      Primitive.zr_mod_const_get_m(inner, segment, inherit, later)
    end
    # rb_mod_const_source_location names the whole path.
    raise TypeError, "#{name} does not refer to class/module" unless scope.is_a?(Module)

    Primitive.zr_mod_const_source_location_m(scope, last, inherit, scopes.any? { |s| !s.empty? })
  end

  # What a constant lookup reaches when no scope has the name. A
  # program overrides it to supply a value. The message names the scope
  # by its `name`, or by its `inspect` when that is nil, as ruby's
  # name_err_mesg_receiver_name does; a program's override counts.
  def const_missing(name)
    return raise(NameError.new("uninitialized constant #{name}", name, receiver: self)) if equal?(Object)

    raise NameError.new("uninitialized constant #{Module.const_scope_shown(self)}::#{name}", name, receiver: self)
  end

  # `refine C do ... end`: the methods go in a holder module, never on
  # C itself, so they stay invisible until a `using` of this module.
  # `refine` is a builtin (zr_mod_refine), which reads the refinements in
  # use at its call before a ruby frame clears them. They also apply in
  # the block, after the block's own.
  def refine_under(outer, target, &block)
    Primitive.attr! :hidden
    raise ArgumentError, +"no block given" unless block
    raise ArgumentError, +"can't pass a Proc as a block to Module#refine" if Primitive.zr_proc_passed_p_m(block)
    raise TypeError, "wrong argument type #{conversion_name(target)} (expected Class or Module)" unless target.is_a?(Module)

    table = (@__refinements__ ||= {})
    holder = table[target]
    unless holder
      holder = Primitive.zr_refinement_new(target, @__activated__ ||= [])
      Primitive.zr_hidden_set(holder, :__origin__, self)
      table[target] = holder
      # Array.newarray_optimized? reads the refinements of Array.
      Primitive.zr_hidden_set(Array, :__refined__, [*Primitive.zr_hidden_get(Array, :__refined__), holder]) if target.equal?(Array)
    end
    Primitive.zr_hidden_set(holder, :__outer__, outer) if outer
    Primitive.zr_refine_body(block, holder)
    holder
  end

  private :refine

  def refinements = @__refinements__ ? @__refinements__.values : []

  # `using` does its work where it is written, which the compiler sees;
  # anywhere else it is the refusal. A block, where ruby permits it,
  # reaches this too, and an argument that is no Module is the TypeError
  # of rb_using_module.
  def using(mod)
    raise TypeError, "wrong argument type #{Primitive.zr_class_name_of(mod)} (expected Module)" unless mod.is_a?(Module)

    raise RuntimeError, +"Module#using is not permitted in methods"
  end
  private :using

  # `Module.used_modules` and `Module.used_refinements` are builtins
  # (zr_mod_used_modules): a compiled ruby frame starts with no
  # refinements in use, so only a frame that the kernel pushes still has
  # the entry that the call site filled.
end

module Kernel
  # On the class where the call is, as rb_f_autoload registers.
  def autoload(name, feature)
    path = File.path(feature)
    raise ArgumentError, +"empty feature name" if path.empty?
    file = Kernel.feature_file(path)
    Primitive.zr_autoload_computed(Kernel, Module.instance_method(:autoload_name).bind_call(Kernel, name), path,
                                   Primitive.zr_eval_cref, Kernel.loaded_feature?(path, file), file)
  end
  # rb_f_autoload_relative (ruby 4.1): `autoload` of a feature taken from
  # the directory of the caller's file.
  def autoload_relative(name, feature)
    name = Module.instance_method(:autoload_name).bind_call(Kernel, name)
    path = Kernel.relative_feature(feature)
    file = Kernel.feature_file(path)
    Primitive.zr_autoload_computed(Kernel, name, path, Primitive.zr_eval_cref, Kernel.loaded_feature?(path, file), file)
  end

  # rb_f_autoload_p: the class of the caller's cref, as `autoload` uses.
  def autoload?(name, inherit = true) = Primitive.zr_cref_lookup_class(Primitive.zr_eval_cref).autoload?(name, inherit)
  private :autoload, :autoload_relative, :autoload?

  # The absolute path of `feature` from the directory of the file that
  # called autoload_relative, as rb_mod_autoload_relative makes it. Code
  # of an eval that names no file has none.
  def self.relative_feature(feature)
    Primitive.attr! :hidden
    path = File.path(feature)
    file = Primitive.zr_caller_file
    if file.nil? || (Primitive.zr_caller_eval_p && file.start_with?("(eval"))
      raise LoadError, +"cannot infer basepath (autoload_relative called without file context)"
    end

    file = File.realpath(file) if File.exist?(file)
    File.absolute_path(path, File.dirname(file))
  end
end

# The holder that `Module#refine` makes. It has no name of its own; it
# shows the pair that it represents.
class Refinement
  def target = Primitive.zr_refined_class(self)

  # A module's OWN methods copied in at the visibility they were
  # declared with. Ruby copies rather than includes, so what the module
  # inherits stays out.
  def import_methods(*modules)
    modules.each do |mod|
      raise TypeError, "wrong argument type #{conversion_name(mod)} (expected Module)" unless mod.instance_of?(Module)
    end
    # rb_mod_import_methods warns for each module first, then copies the
    # methods one at a time, so the ones before a method that cannot be
    # copied stay. Only a method written as a `def` in Ruby can be copied,
    # not a C method, an attr, a define_method or an alias.
    modules.each do |mod|
      warn "#{mod.inspect} has ancestors, but Refinement#import_methods doesn't import their methods", uplevel: 1 if mod.ancestors.size > 1
    end
    modules.each do |mod|
      private_names = mod.private_instance_methods(false)
      (mod.instance_methods(false) + private_names).each do |name|
        ok = Primitive.zr_mod_import_ok_p(mod, name)
        ok = TracePoint.const_get(:BUILTIN_LINES, false).key?("#{mod}##{name}") if ok.nil?
        raise ArgumentError, "Can't import method which is not defined with Ruby code: #{mod}##{name}" unless ok

        define_method(name, mod.instance_method(name))
        Primitive.zr_mod_import_mark(self, name)
        private name if private_names.include?(name)
      end
    end
    self
  end
  private :import_methods

  # Ruby 3.2 took these away from a refinement.
  undef_method :append_features, :prepend_features, :extend_object
end

# main's own, on the toplevel object's singleton class, as CRuby puts it.
class << self
  # Only the compiler activates a refinement, where the source writes
  # the `using`; the method itself is the refusal every other spot gets.
  def using(mod)
    raise TypeError, "wrong argument type #{Primitive.zr_class_name_of(mod)} (expected Module)" unless mod.is_a?(Module)

    raise RuntimeError, +"main.using is permitted only at toplevel"
  end

  private :using
end

class << Module
  # The helpers of Module#const_get, #const_defined? and
  # #const_source_location are Module's own, not a module's: a module can
  # define a method of the same name (the config gem's `const_name`),
  # which a send to the module would reach, where ruby's C calls none.

  STRING_TO_SYM = String.instance_method(:to_sym)
  private_constant :STRING_TO_SYM

  # A Symbol, a String, or what to_str makes of the name.
  # rb_to_id: bytes that make no Symbol raise as String#to_sym does.
  def const_name(name)
    Primitive.attr! :hidden
    return name if name.is_a?(Symbol)

    text = String.try_convert(name) or raise TypeError, "no implicit conversion of #{conversion_name(name)} into String"
    STRING_TO_SYM.bind_call(text) unless text.valid_encoding?
    text
  end

  # Each segment of the path `name`, from `mod`, resolved by the block
  # from the scope before it, with a flag that tells whether an earlier
  # segment resolved. The last value is the return value.
  def walk_const_path(mod, name, segments = name.split("::", -1))
    Primitive.attr! :hidden
    scope = mod
    seen = 0
    segments.each_index do |i|
      segment = segments[i]
      if segment.empty?
        raise NameError.new("wrong constant name #{name}", name, receiver: mod) unless i.zero?

        scope = Object
      else
        # rb_mod_const_get: a "::" that ends the path is wrong before the
        # name in front of it is looked up.
        raise NameError.new("wrong constant name #{name}", name, receiver: mod) if i == segments.size - 2 && segments.last.empty?
        # rb_mod_const_get names the whole path.
        raise TypeError, "#{name} does not refer to class/module" unless scope.is_a?(Module)

        scope = yield(scope, segment, seen.positive?)
        seen += 1
      end
    end
    scope
  end

  # zr_const_wide_name_p (lib/zr/runtime/kernel/const.rb): whether a name
  # with a character past ASCII names a constant, read by character in
  # its own encoding (ISO-8859-15, Shift_JIS or EUC-JP too): an uppercase
  # or titlecase letter first, then letters, digits, `_` and characters
  # past ASCII. A character that has no Unicode form is no letter.
  def const_name?(name)
    Primitive.attr! :hidden
    return false unless name.valid_encoding?

    lead, *rest = name.chars
    return false unless lead.ascii_only? ? lead.match?(/\A[A-Z]\z/) : capital?(lead)

    rest.all? { |char| !char.ascii_only? || char.match?(/\A\w\z/) }
  end

  def capital?(char)
    Primitive.attr! :hidden
    char = char.encode(Encoding::UTF_8) unless char.encoding == Encoding::UTF_8
    char.match?(/\A[\p{Lu}\p{Lt}]\z/)
  rescue EncodingError
    false
  end

  # How an `uninitialized constant` message names the scope `mod`: its
  # `name`, or its `inspect` when that is nil, as a String.
  def const_scope_shown(mod)
    Primitive.attr! :hidden
    shown = mod.__send__(:name)
    (shown.nil? ? mod.__send__(:inspect) : shown).to_s
  end
end

# A module is made by Module.new alone: ruby undefines allocate on
# Module's singleton class, and Class.allocate is Class's own again.
class << Module
  undef_method :allocate
end

# A class is not a module to mix in or to refine with: CRuby undefines
# these for Class. It comes last, after Module#refine.
class Class
  undef_method :module_function, :append_features, :prepend_features, :extend_object, :refine
end
