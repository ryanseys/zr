# frozen_string_literal: true

require_relative "../../lib/zr/hir"
require_relative "../../lib/zr/runtime/lib/zr/eval/world"
require_relative "../../lib/zr/eval/interpreter/evaluate"

module Zr
  class Eval
    # The runtime's part of the front end's setup (runtime/lib/zr/eval/
    # runtime.rb). On CRuby the walk and the front end share ruby's own
    # separators, so there is nothing to set aside.
    class Runtime
      def self.plain_separators = yield
      def self.compiling = yield
    end
  end

  module Test
    # Runs the tree-walking interpreter (lib/zr/eval/interpreter/tree.rb) on CRuby,
    # so its tests take milliseconds and build nothing. The interpreter
    # reaches the runtime only through `Eval::World`, whose methods call
    # the kernel. Here each one is plain Ruby over CRuby's own reflection.
    #
    # A cref is a Cref, and the lexical scope of the code that walks is
    # always the scope it was written in: CRuby cannot read a caller's
    # cref, so a walked block that `class_exec` runs keeps its own. A
    # Binding has one scope, its `local_variables`.
    module InterpreterWorld
      # A lexical scope: its module, the scope outside it, the default
      # visibility of a `def` (0 public, 1 private, 2 protected), and
      # whether `module_function` is on.
      Cref = Struct.new(:klass, :outer, :vis, :modfn)

      # The cref of a walked eval's caller: the top level, or the bodies
      # of `nesting`, outermost first.
      #: (?Array[Module] nesting) -> Cref
      def self.cref(nesting = [])
        nesting.reduce(Cref.new(::Object, nil, 0, false)) { |outer, mod| Cref.new(mod, outer, 0, false) }
      end

      # Walks `source` as `eval(source, scope)` would, under `nesting`.
      #: (String source, Binding scope, ?nesting: Array[Module], ?block: Proc?, ?file: String, ?line: Integer) -> untyped
      def self.eval(source, scope, nesting: [], block: nil, file: "(eval)", line: 1)
        Eval::Interpreter.evaluate(source, scope, file: file, line: line, self_: scope.receiver, cref: cref(nesting), block: block)
      end

      # A `return` of a walked string, which `in_method` catches as the
      # method that called eval would return.
      RETURN = :walk_return

      # Runs the block as the body of a method that evals: a `return` in a
      # walked string returns its value from here.
      #: [T] () { () -> T } -> (T | untyped)
      def self.in_method(&) = catch(RETURN, &)

      # The `[$~, $_]` cell of a Binding's frame, read and written through
      # the Binding.
      class Svars
        NAMES = ["$~", "$_"].freeze

        #: (Binding b) -> void
        def initialize(b)
          @binding = b
        end

        #: (Integer i) -> untyped
        def [](i) = @binding.eval(NAMES.fetch(i))

        #: (Integer i, untyped value) -> untyped
        def []=(i, value)
          Thread.current[:walk_svar] = value
          @binding.eval("#{NAMES.fetch(i)} = Thread.current[:walk_svar]")
        end
      end

      # The modules of `cref`, innermost first, without the top level.
      #: (Cref cref) -> Array[Module]
      def self.lexical(cref)
        out = [] #: Array[Module]
        while cref&.outer
          out << cref.klass
          cref = cref.outer
        end
        out
      end

      # The plain Ruby `World`.
      module Methods
        CALLER = :caller_cref
        # A block with no locals around it (`bare_binding`).
        BARE = proc { binding }

        def cref = CALLER
        def same?(a, b) = a.equal?(b) || a == CALLER || b == CALLER
        def cref_push(mod, outer) = Cref.new(mod, outer, 0, false)
        def cref_klass(cref) = cref.klass
        def cref_definee(cref) = cref.klass
        def cref_lexical(cref) = cref
        def walk_cref(here, _outer) = here
        def vm_stack_args(_n) = nil
        def rescue_meta(meta, _line) = meta

        PRIVATE = %i[initialize initialize_copy initialize_clone initialize_dup respond_to_missing?].freeze

        def definition_vis(name, cref)
          return 1 if PRIVATE.include?(name) || cref.modfn

          cref.vis
        end

        def module_function?(cref) = cref.modfn

        def set_vis(cref, vis)
          cref.vis = vis
          cref.modfn = false
        end

        def set_module_function(cref) = cref.modfn = true
        def require_hidden(path) = require(path)
        def errinfo = $!
        def walk_enter(_box) = nil
        def walk_leave(_outer) = nil
        def walk_box = nil
        # CRuby shows the walker's own frames: there is no frame to push.
        def walk_meta(_kind, _name, _owner, _parent, file:, evaled:, box: nil) = nil
        def eval_caller_meta = nil

        def walk_send(_at, recv, name, args, kwargs:, blk:, private:, vcall: false)
          kwargs ||= {}
          private ? recv.__send__(name, *args, **kwargs, &blk) : recv.public_send(name, *args, **kwargs, &blk)
        end

        def walk_yield(_at, blk, args, kwargs) = kwargs ? blk.call(*args, **kwargs) : blk.call(*args)
        def bare_binding(obj) = obj.instance_exec(&BARE)
        def walk_signature(_method, _rows, _arity) = nil

        def singleton_of(obj)
          obj.singleton_class
        rescue ::TypeError
          obj.class
        end

        def binding_scopes(b) = [b.local_variables]
        def binding_get(b, _depth, index) = b.local_variable_get(b.local_variables.fetch(index))
        def binding_set(b, _depth, index, v) = b.local_variable_set(b.local_variables.fetch(index), v)
        def binding_parameters(b)
          name = b.eval("__method__") or return nil
          b.receiver.method(name).parameters
        end

        def binding_svars(b) = Svars.new(b)
        def binding_return(_b, v) = throw(RETURN, v)
        # CRuby's Binding#local_variable_set adds each new name itself.
        def binding_push(_b, _names) = nil
        def coverage_begin(_path, _loaded) = nil
        def coverage_claim(_owner, _name, _cover) = nil
        def coverage_line(_row, _line, _jump) = nil
        def coverage_branch(_id) = nil

        def binding_method(b)
          name = b.eval("__method__") or return nil
          [name, b.receiver.method(name).owner]
        end

        def nesting(cref) = InterpreterWorld.lexical(cref)
        # CRuby has no way to chill a String that exists.
        def chill(string) = string
        def path(string) = string

        def const_get(cref, name)
          found = InterpreterWorld.lexical(cref).find { |mod| mod.const_defined?(name, false) }
          found ? found.const_get(name, false) : cref.klass.const_get(name)
        end

        def const_defined?(cref, name)
          InterpreterWorld.lexical(cref).any? { |mod| mod.const_defined?(name, false) } || cref.klass.const_defined?(name)
        end

        def const_get_at(scope, name) = scope.const_get(name)
        def const_defined_at?(scope, name) = scope.const_defined?(name)
        def const_set(klass, name, value, _at = nil) = klass.const_set(name, value)

        # The `class` and `module` keywords: open the constant, or define it.
        def class_define(_at, base, name, sup, given, _scoped) # rubocop:disable Metrics/ParameterLists -- World.class_define's
          base.const_defined?(name, false) ? base.const_get(name, false) : base.const_set(name, Class.new(given ? sup : Object))
        end

        def module_define(_at, base, name, _scoped)
          base.const_defined?(name, false) ? base.const_get(name, false) : base.const_set(name, Module.new)
        end

        def cvar_get(cref, name) = cref.klass.class_variable_get(name)
        def cvar_defined?(cref, name) = cref.klass.class_variable_defined?(name)
        def cvar_set(cref, name, value) = cref.klass.class_variable_set(name, value)

        def gvar_get(name) = ::TOPLEVEL_BINDING.eval(name.to_s)
        def gvar_defined?(name) = ::TOPLEVEL_BINDING.eval("defined?(#{name})")
        def frozen_string(text, kind) = kind == 3 ? text.dup.freeze : -text
        def debug_string(text, _file, _line) = text.dup.freeze
        # CRuby keeps no record of an alias that the walker can read.
        def alias_of(_name) = nil

        def gvar_set(_shown, name, value)
          ::TOPLEVEL_BINDING.local_variable_set(:__walk_value__, value)
          ::TOPLEVEL_BINDING.eval("#{name} = __walk_value__")
        end

        def gvar_alias(new_name, old_name) = ::TOPLEVEL_BINDING.eval("alias #{new_name} #{old_name}")
        def alias_method(klass, new_name, old_name) = klass.send(:alias_method, new_name, old_name)
      end

      Eval::World.singleton_class.prepend(Methods)

      # The core helper that the front end sends for `/a#{b}/`
      # (lib/zr/runtime/core/regexp.rb), as plain Ruby: the fragments
      # joined, compiled with the literal's option bits.
      unless ::Regexp.respond_to?(:interpolated, true)
        ::Regexp.define_singleton_method(:interpolated) { |fragments, bits, _pinned| new(fragments.join, bits & 7).freeze }
      end
      # The same for a literal (`Regexp.literal`): the source in the
      # encoding that a flag letter pins, by its index.
      unless ::Regexp.respond_to?(:literal, true)
        ::Regexp.define_singleton_method(:literal) do |source, bits, pinned|
          new(pinned ? source.dup.force_encoding(::Encoding.list.fetch(pinned)) : source, bits & 7)
        end
      end
    end
  end
end
