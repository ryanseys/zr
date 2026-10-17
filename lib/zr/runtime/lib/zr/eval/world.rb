# frozen_string_literal: true

# The part of the tree-walking interpreter that only the runtime can supply.
#
# A program on wasm cannot write machine code while it runs: a module's
# code is fixed when the engine instantiates it, and WASI gives a guest
# no way to load a second module. So a program there includes only the
# front end and walks the tree it builds (lib/zr/eval/interpreter.rb). The
# walk is ordinary Ruby and reaches the program through ordinary calls
# (`__send__`, `define_method`, `instance_variable_get`) for all but
# the tables that the compiler reaches through inline caches.
# Those are here.

module Zr
  class Eval
    # The lexical scope, the scopes of a Binding, and the constant,
    # class-variable and global tables. Every method here is in place of
    # one that the compiler emits inline, and returns the same value.
    module World
      module_function

      # The lexical scope of the calling frame (the caller's, because
      # this method's own frame is on top). A block that the walk made
      # reads it to see whether `class_eval` or `instance_exec` gave it
      # a scope other than the one where it was written.
      def cref = Primitive.zr_eval_cref

      # Two crefs, or any two Values, as the same object. A cref accepts
      # no message, so it cannot be compared by a method call on it.
      def same?(a, b) = Primitive.zr_same_p(a, b)

      # The address of the compiled toplevel of the program's file at
      # `path`, as an Integer, or nil.
      def unit_for(path) = Primitive.zr_unit_for(path)

      # A lexical scope for a class or module body, which a `def` in it
      # defines into and a constant in it is read under.
      def cref_push(mod, outer) = Primitive.zr_cref_push(mod, outer)
      # The module a cref names, and the innermost cref that is a
      # lexical scope rather than an eval's.
      def cref_klass(cref) = Primitive.zr_cref_klass(cref)
      # The class that a `def`, an `alias` or an `undef` changes. Under
      # `1.instance_eval` there is none, and it raises TypeError.
      def cref_definee(cref) = Primitive.zr_cref_definee(cref)
      # The `class` and `module` keywords: open the constant, or define
      # it, as compiled code does.
      def class_define(base, name, sup, given, scoped) = Primitive.zr_class_define_m(base, name, sup, given, scoped)
      def module_define(base, name, scoped) = Primitive.zr_module_define_scoped_m(base, name, scoped)
      def cref_lexical(cref) = Primitive.zr_cref_lexical(cref)
      # The visibility that a `def` under `cref` gets: 0 public, 1 private,
      # 2 protected; and whether `module_function` requests a copy on
      # the singleton class.
      def definition_vis(name, cref) = Primitive.zr_definition_vis_m(name, cref)
      def module_function?(cref) = Primitive.zr_cref_modfn_p(cref)
      # What a bare `private`, `public`, `protected` or `module_function`
      # in a body writes: the body's own visibility, which lives in its
      # cref and not in any frame the walk has.
      def set_vis(cref, vis) = Primitive.zr_cref_set_vis(cref, vis)
      def set_module_function(cref) = Primitive.zr_cref_set_modfn(cref)

      # While the walk runs, the caller of the runtime is the program,
      # not the interpreter's own file, which loaded hidden from the
      # program. So a constant that the string defines is the program's,
      # and so is a require that it makes.
      #: () -> void
      def walk_enter = Primitive.zr_walk_enter
      #: () -> void
      def walk_leave = Primitive.zr_walk_leave

      # `class << obj` and `obj.instance_eval`: the singleton class, or
      # the class itself where the object can hold no singleton.
      def singleton_of(obj) = Primitive.zr_eval_class_of(obj)

      # The scopes of a Binding, innermost first, each an Array of the
      # names of its slots; and one slot of one scope.
      #: (Binding b) -> Array[Array[Symbol?]]
      def binding_scopes(b) = Primitive.zr_binding_scopes(b)
      def binding_get(b, depth, index) = Primitive.zr_binding_get(b, depth, index)
      def binding_set(b, depth, index, v) = Primitive.zr_binding_set(b, depth, index, v)
      def binding_parameters(b) = Primitive.zr_binding_parameters(b)

      # What the walk reads of the frame that called eval, through its
      # Binding: the `[$~, $_]` cell, a `return` from its method, and that
      # method's name and owner (`[name, owner]`, or nil).
      def binding_svars(b) = Primitive.zr_binding_svars(b)
      def binding_return(b, v) = Primitive.zr_binding_return(b, v)
      def binding_method(b) = Primitive.zr_binding_method(b)
      # The new locals of a `Binding#eval` string, as one new scope inside
      # the Binding's, as the eval compiler leaves them.
      def binding_push(b, names) = Primitive.zr_binding_push_m(b, names)

      # Coverage's counters, for the line events and branch counters of
      # walked code (`Hir::Trace`, `Hir::Cover`).
      def coverage_line(path, line, jump) = Primitive.zr_coverage_line_at_m(path, line, jump)
      def coverage_branch(id) = Primitive.zr_coverage_branch_m(id)

      # `Module.nesting` under `cref`, and a String literal's chill.
      def nesting(cref) = Primitive.zr_cref_nesting(cref)
      def chill(string) = Primitive.zr_str_chill(string)
      # A path from the system, in the locale's encoding (`zr_path_str`).
      def path(string) = Primitive.zr_path_str(string)

      # A bare constant under `cref`, and `scope::Name`, read as the walked
      # program reads them: a constant that only eval support set (Zr,
      # Prism) stays hidden, though these frames are eval support's.
      def const_get(cref, name) = Primitive.zr_walk_const_get_m(cref, name)
      def const_defined?(cref, name) = Primitive.zr_walk_const_defined_m(cref, name)
      def const_get_at(scope, name) = Primitive.zr_walk_const_get_at_m(scope, name)
      def const_defined_at?(scope, name) = Primitive.zr_walk_const_defined_at_m(scope, name)
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
