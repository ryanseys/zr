      # frozen_string_literal: true

      # The walking eval road's half that only the runtime can answer.
      #
      # A program on wasm cannot write machine code while it runs: a module's
      # code is fixed when the engine instantiates it, and nothing in WASI
      # hands a guest a second module. So a program there carries the front
      # end alone and walks the tree it builds (lib/ze0/eval/walk.rb). The
      # walk is ordinary Ruby and reaches the program through ordinary calls
      # -- `__send__`, `define_method`, `instance_variable_get` -- for
      # everything but the tables the compiler reaches through inline caches.
      # Those are here.

module Ze0
  class Eval
    # The lexical scope, the scopes a Binding names, and the constant,
    # class-variable and global tables. Every method here stands for one
    # the compiler emits inline, and answers what that one answers.
    module World
      module_function

      # The lexical scope the frame that asked for the eval stands in,
      # and one scope inside it.
      def cref_under(mod, outer) = Primitive.zr_eval_cref_under(mod, outer)
      # A lexical scope for a class or module body, which a `def` in it
      # defines into and a constant in it is read under.
      def cref_push(mod, outer) = Primitive.zr_cref_push(mod, outer)
      # The module a cref names, and the innermost cref that is a
      # lexical scope rather than an eval's.
      def cref_klass(cref) = Primitive.zr_cref_klass(cref)
      def cref_lexical(cref) = Primitive.zr_cref_lexical(cref)
      # The visibility a `def` under `cref` gets: 0 public, 1 private,
      # 2 protected; and whether `module_function` asks for a copy on
      # the singleton class.
      def definition_vis(name, cref) = Primitive.zr_definition_vis_m(name, cref)
      def module_function?(cref) = Primitive.zr_cref_modfn_p(cref)
      # What a bare `private`, `public`, `protected` or `module_function`
      # in a body writes: the body's own visibility, which lives in its
      # cref and not in any frame the walk has.
      def set_vis(cref, vis) = Primitive.zr_cref_set_vis(cref, vis)
      def set_module_function(cref) = Primitive.zr_cref_set_modfn(cref)

      # While the walk runs, what asks the runtime is the program and
      # not the road's own file, which loaded out of the program's
      # sight: a constant the string defines is the program's, and so
      # is a require it makes.
      def walk_enter = Primitive.zr_walk_enter
      def walk_leave = Primitive.zr_walk_leave

      # `class << obj` and `obj.instance_eval`: the singleton class, or
      # the class itself where the object can hold no singleton.
      def singleton_of(obj) = Primitive.zr_eval_class_of(obj)

      # The scopes a Binding names, innermost first, each an Array of
      # the names its slots hold; and one slot of one scope.
      def binding_scopes(b) = Primitive.zr_binding_scopes(b)
      def binding_get(b, depth, index) = Primitive.zr_binding_get(b, depth, index)
      def binding_set(b, depth, index, v) = Primitive.zr_binding_set(b, depth, index, v)
      def binding_add(b, name) = Primitive.zr_binding_add(b, name)
      def binding_receiver(b) = Primitive.zr_binding_receiver(b)
      def binding_cref(b) = Primitive.zr_binding_cref(b)
      def binding_parameters(b) = Primitive.zr_binding_parameters(b)

      # A bare constant under `cref`, and `scope::Name`.
      def const_get(cref, name) = Primitive.zr_const_get_m(cref, name)
      def const_defined?(cref, name) = Primitive.zr_const_defined_m(cref, name)
      def const_get_at(scope, name) = Primitive.zr_const_get_at_m(scope, name)
      def const_defined_at?(scope, name) = Primitive.zr_const_defined_at_m(scope, name)
      def const_set(klass, name, value) = Primitive.zr_const_set_m(klass, name, value)

      def cvar_get(cref, name) = Primitive.zr_cvar_get_m(cref, name)
      def cvar_defined?(cref, name) = Primitive.zr_cvar_defined_m(cref, name)
      def cvar_set(cref, name, value) = Primitive.zr_cvar_set_m(cref, name, value)

      def gvar_get(name) = Primitive.zr_gvar_get_m(name)
      def gvar_defined?(name) = Primitive.zr_gvar_defined_m(name)
      def gvar_set(shown, name, value) = Primitive.zr_gvar_hooked_m(shown, name, value)
      def gvar_alias(new_name, old_name) = Primitive.zr_gvar_alias_m(new_name, old_name)

      # `alias :"#{a}" :"#{b}"` on a module.
      def alias_method(klass, new_name, old_name) = Primitive.zr_alias_value(klass, new_name, old_name)
    end
  end
end
