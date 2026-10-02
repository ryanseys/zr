# frozen_string_literal: true

# A Binding represents a scope: its locals, its self and the lexical
# scope that its constants read. It shares the scope's slots rather
# than copying them, so a write on either side is seen on both, and a
# local declared after the capture is already in it.
class Binding
  Primitive.zr_undef_alloc(self)

  class << self
    undef_method :new
  end

  def receiver = Primitive.zr_binding_receiver(self)

  def source_location = [Primitive.zr_binding_file(self), Primitive.zr_binding_line(self)]

  def local_variables
    scopes.flatten.compact.uniq
  end

  def local_variable_defined?(name) = !place(local_name(name)).nil?

  def local_variable_get(name)
    name = local_name(name)
    at = place(name) or raise NameError.new("local variable '#{name}' is not defined for #{inspect}", name, receiver: self)
    Primitive.zr_binding_get(self, at[0], at[1])
  end

  # A name that is in no scope becomes the Binding's own, in a scope
  # inside the one it represents, as in ruby.
  def local_variable_set(name, value)
    name = local_name(name)
    Primitive.zr_binding_add(self, name.to_s) unless place(name)
    at = place(name)
    Primitive.zr_binding_set(self, at[0], at[1], value)
  end

  # `it` or the numbered parameters the innermost scope takes.
  def implicit_parameters
    names = Primitive.zr_binding_scopes(self).first
    return [:it] if names.include?(IT)

    names.select { |name| numbered?(name) }
  end

  def implicit_parameter_defined?(name) = !implicit_place(name).nil?

  def implicit_parameter_get(name)
    at = implicit_place(name)
    raise NameError.new("implicit parameter '#{name}' is not defined for #{inspect}", name.to_sym, receiver: self) unless at

    Primitive.zr_binding_get(self, 0, at)
  end

  # Eval support defines this again over the compiler that the program
  # links in, as it does Kernel#eval.
  def eval(source, file = nil, line = 1) = Primitive.zr_unimplemented("eval reached in a program built without the compiler")

  IRB_SESSION = []
  private_constant :IRB_SESSION

  def self.irb_session=(load)
    Primitive.attr! :hidden
    IRB_SESSION[0] = load
  end

  # The load that `irb` arms, done once: irb's own Binding#irb handles
  # every call after the first.
  def self.irb_session
    Primitive.attr! :hidden
    IRB_SESSION.pop
  end

  # CRuby's prelude: the first `binding.irb` requires irb, whose own
  # Binding#irb replaces this one, and then calls it. A program that
  # calls `irb` by name includes lib/zr/runtime/lib/zr/irb_session.rb before its
  # body. That file arms the require, so irb joins $LOADED_FEATURES only
  # on that first call.
  #
  # ruby suppresses the bundled-gem warning around its require, and uses
  # `Gem::BUNDLED_GEMS.force_activate` as a fallback, because irb (with
  # reline and rdoc) is a bundled gem there. Here irb is part of the
  # library that the program was compiled against, so there is no warning
  # and nothing to activate. A program that does not include irb raises
  # the same LoadError as a ruby without irb.
  def irb(...)
    Primitive.attr! :ruby
    load = Binding.send(:irb_session) or raise LoadError, "cannot load such file -- irb"

    load.call
    # A send of the core library reaches the core's own row, so the call
    # goes through the row irb.rb wrote.
    Binding.instance_method(:irb).bind_call(self, ...)
  end
  # CRuby's prelude aliases irb to itself, so irb.rb's definition over
  # it warns of no redefinition.
  alias irb irb

  # A copy refers to the same scope, but a local that it adds is its own,
  # as binding_copy makes it.
  def dup = super

  def clone = super()

  # The lowering's name for `it`, which no program can spell.
  IT = :"%it"
  private_constant :IT

  private

  # The slot of an implicit parameter in the innermost scope, or nil.
  def implicit_place(name)
    Primitive.attr! :hidden
    name = symbol_name(name)
    raise NameError.new("'#{name}' is not an implicit parameter", name, receiver: self) unless name == :it || numbered?(name)

    Primitive.zr_binding_scopes(self).first.index(name == :it ? IT : name)
  end

  # `_1` to `_9`, which a block that reads them takes as parameters.
  def numbered?(name)
    Primitive.attr! :hidden
    /\A_[1-9]\z/.match?(name)
  end

  # The name of a local as check_local_id takes it: a numbered parameter
  # is no local variable, and a name that is no identifier is a wrong one.
  def local_name(name)
    Primitive.attr! :hidden
    name = symbol_name(name)
    raise NameError.new("numbered parameter '#{name}' is not a local variable", name, receiver: self) if numbered?(name)
    raise NameError.new("wrong local variable name '#{name}' for #{inspect}", name, receiver: self) unless /\A[a-z_\u0080-\u{10ffff}][[:word:]\u0080-\u{10ffff}]*\z/.match?(name)

    name
  end

  # The name of a local, as ruby takes one: a Symbol or a String.
  def symbol_name(name)
    Primitive.attr! :hidden
    return name if name.is_a?(Symbol)
    return name.to_sym if name.is_a?(String)

    raise TypeError, "#{name.inspect} is not a symbol nor a string"
  end

  # `[depth, index]` of `name`, or nil when no scope contains it. A hidden
  # local of the lowering keeps its slot but has no name.
  def place(name)
    Primitive.attr! :hidden
    scopes.each_index do |depth|
      i = scopes[depth].index(name)
      return [depth, i] if i
    end
    nil
  end

  # The names in each scope, innermost first, with hidden ones dropped.
  def scopes
    Primitive.attr! :hidden
    Primitive.zr_binding_scopes(self).map { |names| names.map { |n| named?(n) ? n : nil } }
  end

  def named?(name)
    Primitive.attr! :hidden
    /\A[a-z_][A-Za-z0-9_]*\z/.match?(name.to_s) && !numbered?(name)
  end
end

module Kernel
  # The scope of this call.
  def binding = Primitive.zr_binding

  # The names in the caller's scope, which are the names of its Binding.
  def local_variables = Primitive.zr_binding.local_variables
end
