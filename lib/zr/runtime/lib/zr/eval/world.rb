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
      # it, as compiled code does, under a frame of `at` (Tree#frame_at),
      # whose file and line the constant records.
      def class_define(at, base, name, sup, given, scoped) = Primitive.zr_walk_class_define_m(at, base, name, sup, given, scoped)
      def module_define(at, base, name, scoped) = Primitive.zr_walk_module_define_m(at, base, name, scoped)
      def cref_lexical(cref) = Primitive.zr_cref_lexical(cref)
      # The cref of a walked block that an exec runs (`here`), over the
      # block's own (`outer`) in place of the walker's.
      def walk_cref(here, outer) = Primitive.zr_walk_cref_m(here, outer)
      # Raises SystemStackError when ruby's VM stack would not hold the
      # receiver and `n` arguments, as a compiled call checks.
      def vm_stack_args(n) = Primitive.zr_vm_stack_args_m(n + 1)
      # The meta of a rescue clause whose `begin` is at `line`, in the
      # scope of `meta` (kernel/eval_walk.rb).
      def rescue_meta(meta, line) = Primitive.zr_walk_rescue_meta_m(meta, line)
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

      # The frames of walked code (kernel/eval_walk.rb). A FrameMeta for a
      # scope of the string, as an Integer: `kind` is a key of KINDS.
      KINDS = { def: 1, class: 3, module: 4, block: 5, sclass: 6, top: 8, eval: 9, compiled: 10 }.freeze
      # The scope of a block with no locals around it (`bare_binding`).
      BARE = proc { Primitive.zr_own_binding }

      #: (Symbol kind, Symbol? name, Module? owner, Integer? parent, file: String, evaled: bool, ?box: untyped) -> Integer?
      def walk_meta(kind, name, owner, parent, file:, evaled:, box: nil)
        Primitive.zr_walk_meta_m(KINDS.fetch(kind), name, owner, file, parent, evaled, box)
      end
      # The meta of the frame that called eval, whose label an eval's
      # code shows.
      #: () -> Integer?
      def eval_caller_meta = Primitive.zr_walk_caller_meta_m

      # A call from walked code, under a frame of `at` (`[meta, line,
      # self]`): a private call goes as one with no receiver, any other as
      # one with a receiver, so a protected method sees the walked self. A
      # bare identifier (`vcall`) that finds no method raises NameError,
      # with the locals of the walked scope.
      # `new` is true for a `new` that ruby compiles to opt_new.
      #: (Array[untyped]? at, untyped recv, Symbol name, Array[untyped] args, kwargs: Hash[Symbol, untyped]?, blk: Proc?, private: bool, ?vcall: bool, ?new: bool) -> untyped
      def walk_send(at, recv, name, args, kwargs:, blk:, private:, vcall: false, new: false)
        mode = if vcall then 1
               elsif private then 0
               else 2
               end
        mode += 512 if new
        return Primitive.zr_walk_send_m(at, recv, name, args, blk, mode) unless kwargs

        Primitive.zr_walk_send_m(at, recv, name, [*args, kwargs], blk, mode + 256)
      end

      # A `yield` from walked code to `blk`, under a frame of `at`, as
      # walk_send calls.
      #: (Array[untyped]? at, Proc blk, Array[untyped] args, Hash[Symbol, untyped]? kwargs) -> untyped
      def walk_yield(at, blk, args, kwargs)
        return Primitive.zr_walk_yield_m(at, blk, args, false) unless kwargs

        Primitive.zr_walk_yield_m(at, blk, [*args, kwargs], true)
      end

      # A Binding of `obj` with no locals: the frame of a block that sees
      # none.
      #: (untyped obj) -> Binding
      def bare_binding(obj) = obj.instance_exec(&BARE)

      # While the walk runs, the caller of the runtime is the program,
      # not the interpreter's own file, which loaded hidden from the
      # program. So a constant that the string defines is the program's,
      # and so is a require that it makes. `box` is the Ruby::Box of the
      # walked code, or nil for main: the box that these World calls read
      # and write in. walk_enter returns the box of the walk around it,
      # which walk_leave puts back.
      #: (untyped box) -> untyped
      def walk_enter(box) = Primitive.zr_walk_enter(box)
      #: (untyped outer) -> void
      def walk_leave(outer) = Primitive.zr_walk_leave(outer)
      # The box of the walk that runs now, or nil.
      def walk_box = Primitive.zr_walk_box

      # A method that the walk defined with define_method: its
      # `parameters` and `arity` are the def's (`rows`, `arity`), not
      # those of the block that runs it.
      def walk_signature(method, rows, arity) = Primitive.zr_walk_describe_m(method, rows, arity)

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
      # The index of the Coverage row of a walk of `path`, or nil before
      # Coverage is set up; then one run of a line in that row.
      def coverage_begin(path, loaded) = Primitive.zr_coverage_begin_m(path, loaded)
      def coverage_line(row, line, jump) = Primitive.zr_coverage_line_at_m(row, line, jump)
      def coverage_branch(id) = Primitive.zr_coverage_branch_m(id)
      # Whether a TracePoint can hear walked code: one is enabled, or the
      # program was built with trace events (Runtime#tracing?).
      def tracing? = Primitive.zr_trace_armed_m || Primitive.zr_trace_built_m
      # Fires the TracePoint event `bit` (a RUBY_EVENT_ bit, with
      # TRACE_LAMBDA for a lambda's block events) of walked code under a
      # frame of `at`, as compiled code fires it; `value` is a closing
      # event's. Returns `value`.
      def walk_trace(at, bit, value) = Primitive.zr_walk_trace_m(at, bit, value)
      # Where the walked code of `proc` (a block, a lambda or a def's body)
      # starts and ends, which its source_location and source_range give.
      def walk_span(proc, span) = Primitive.zr_walk_span_m(proc, span)
      # Coverage's record of the method `name` of `owner`, a def of the
      # walked code at the def site `cover`.
      def coverage_claim(owner, name, cover) = Primitive.zr_walk_coverage_claim_m(owner, name, cover)

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
      def const_set(klass, name, value, at = nil) = Primitive.zr_walk_const_set_m(at, klass, name, value)

      def cvar_get(cref, name) = Primitive.zr_cvar_get_m(cref, name)
      def cvar_defined?(cref, name) = Primitive.zr_cvar_defined_m(cref, name)
      def cvar_set(cref, name, value) = Primitive.zr_cvar_set_m(cref, name, value)

      def gvar_get(name) = Primitive.zr_gvar_get_m(name)
      # A frozen String literal of the walked code (Tree#frozen_string):
      # `kind` 0 interns, 1 interns unless String#freeze is redefined, 2
      # unless String#-@ is, and 3 freezes a copy.
      def frozen_string(text, kind) = Primitive.zr_walk_frozen_m(text, kind)
      # A frozen copy of `text` that names `file:line`, where it was made.
      def debug_string(text, file, line) = Primitive.zr_walk_debug_string_m(text, file, line)
      # The global that `$name` aliases, from the record of an `alias` that
      # ran, or nil (Runtime#alias_of).
      def alias_of(name) = Primitive.zr_gvar_get_m(Hir::Build.alias_record(name))
      # Eval support's own require of a file that the program carries.
      #: (String path) -> bool
      def require_hidden(path) = Primitive.zr_walk_require_hidden_m(path)
      # `$!`, which no global table holds.
      #: () -> Exception?
      def errinfo = Primitive.zr_errinfo
      def gvar_defined?(name) = Primitive.zr_gvar_defined_m(name)
      def gvar_set(shown, name, value) = Primitive.zr_gvar_hooked_m(shown, name, value)
      def gvar_alias(new_name, old_name) = Primitive.zr_gvar_alias_m(new_name, old_name)

      # `alias :"#{a}" :"#{b}"` on a module.
      def alias_method(klass, new_name, old_name) = Primitive.zr_alias_value(klass, new_name, old_name)
    end
  end
end
