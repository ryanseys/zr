# frozen_string_literal: true

require_relative "../../eval"
require_relative "../../hir"
require_relative "../../refused"

module Zr
  class Eval
    # The tree-walking back end of eval (`lib/zr/eval/interpreter.rb`).
    class Interpreter < Eval
      # The tree-walking interpreter, for a program that cannot write
      # machine code while it runs.
      #
      # The front end is the same as the compiler's: the same prism port,
      # `Hir.build`, desugaring and name resolution. Only the back end is
      # different. The eval compiler lowers the tree to IR and writes it
      # into the process. This class evaluates the tree node by node. It
      # calls into the program with the usual Ruby calls (`__send__`,
      # `define_method`, `instance_variable_get`), and uses `Eval::World`
      # for the tables that compiled code reads inline.
      #
      # It is much slower than compiled code; wasm requires this. But it
      # must not give a result different from ruby. It refuses a form that
      # it does not support, with a message that gives the form and the line.
      class Tree
        # @rbs @file: String
        # @rbs @frame: Binding
        # @rbs @once: Hash[Hir::Once, value]?
        # @rbs @frozen: Hash[Hir::FrozenString, String]?
        # @rbs @coverage_row: Integer?
        # @rbs @plain_new: bool?
        # @rbs @regexps: Hash[Hir::RegexpLit | Hir::RegexpOnce, Regexp]?
        # @rbs @svars: svars?
        # @rbs @loaded: bool
        # @rbs @box: untyped

        # A form that the interpreter does not support yet, with its
        # location. The contract lets zr refuse, but not guess.
        class Refused < ::NotImplementedError
          include Zr::Refusal
        end

        # `return`, `break`, `next`, `redo` and `retry` leave a walked body
        # as a raise does (a pending unwind). They are subclasses of
        # Exception, not StandardError, so that a bare `rescue` does not
        # catch them. This applies to walked code and to a compiled method
        # that gets a walked block.
        class Signal < ::Exception; end

        # A signal that carries a value to the frame that its tag names.
        # Each kind's MESSAGE is ruby's error when no frame takes it.
        class Jump < Signal
          attr_reader :value #: value
          attr_reader :tag #: Integer?

          #: (value value, Integer? tag) -> void
          def initialize(value, tag)
            @value = value
            @tag = tag
            super(self.class::MESSAGE)
          end
        end

        class Returning < Jump
          MESSAGE = "unexpected return"
        end

        class Breaking < Jump
          MESSAGE = "break from proc-closure"
        end

        class Nexting < Jump
          MESSAGE = "unexpected next"
        end

        class Redoing < Signal
          attr_reader :tag #: Integer?

          #: (Integer? tag) -> void
          def initialize(tag)
            @tag = tag
            super("unexpected redo")
          end
        end

        class Retrying < Signal
          #: () -> void
          def initialize = super("retry outside of rescue clause")
        end

        # The locals of one scope, by name. A scope that the interpreter
        # makes is a Hash. The scopes outside an eval belong to the calling
        # frame, and `Held` reads them through its `Binding`.
        class Scope
          # @rbs @values: Hash[Symbol, value]

          #: (Array[Symbol] names) -> void
          def initialize(names)
            @values = {}
            names.each { |name| @values[name] = nil }
          end

          #: (Symbol name) -> bool
          def holds?(name) = @values.key?(name)
          #: (Symbol name) -> value
          def get(name) = @values[name]
          #: (Symbol name, value value) -> value
          def set(name, value) = @values[name] = value
          #: () -> Array[Symbol]
          def names = @values.keys
        end

        # A scope of the frame that called eval, through its Binding. Reads
        # and writes go to the frame itself, so the caller sees a local
        # that the string assigns.
        class Held
          # @rbs @binding: Binding
          # @rbs @depth: Integer
          # @rbs @names: Array[Symbol?]

          #: (Binding binding, Integer depth, Array[Symbol?] names) -> void
          def initialize(binding, depth, names)
            @binding = binding
            @depth = depth
            @names = names
          end

          #: (Symbol name) -> bool
          def holds?(name) = !@names.index(name).nil?
          #: () -> Array[Symbol]
          def names = @names.compact

          #: (Symbol name) -> value
          def get(name)
            i = @names.index(name) or return nil
            World.binding_get(@binding, @depth, i)
          end

          #: (Symbol name, value value) -> value
          def set(name, value)
            i = @names.index(name) or return value
            World.binding_set(@binding, @depth, i, value)
          end
        end

        # The context of a node: its self, the lexical scope for constant
        # lookup, the chain of local scopes (innermost first), and the block
        # of the body. In a method, it also has the name and owner that
        # `super` starts from, and the arguments that a bare `super` passes
        # again. `tag` marks the innermost block or loop, which `break`,
        # `next` and `redo` leave. `home` marks the method that a `return`
        # leaves; it is nil when there is no such method. `svars` is the
        # `[$~, $_]` cell of a method or body that the string defines; nil
        # is the cell of the frame that called eval. `meta` is the FrameMeta
        # of the scope (`scope_meta`), under which a call from it runs.
        # @rbs skip -- typed in sig/zr/eval/interpreter/tree.rbs
        Ctx = Data.define(:self_, :cref, :chain, :block, :name, :owner, :args, :kwargs, :tag, :home, :svars, :meta)

        # `frame` is the Binding of the frame that called eval: the scope
        # that a `return`, `$~` and `binding` of the string belong to.
        # `loaded` marks a file that a require walks, which has an absolute
        # path, where an eval's code has none. `box` is the Ruby::Box of the
        # code (nil for main): each walk of it, and each method and block
        # that it defines, runs in that box.
        #: (String file, Binding frame, ?loaded: bool, ?box: untyped) -> void
        def initialize(file, frame, loaded: false, box: nil)
          @file = file
          @frame = frame
          @loaded = loaded
          @box = box
        end

        # The FrameMeta of a scope of the walked code, as World.walk_meta
        # gives it (nil on CRuby), made once for each scope: `kind` and
        # `name` as the compiler gives them, the `owner` of a method, and
        # the meta of the scope around a block (or of eval's caller).
        #: (Symbol kind, Symbol? name, Module? owner, Integer? parent) -> Integer?
        def scope_meta(kind, name, owner, parent)
          key = [kind, name, owner, parent, @file, @loaded, @box]
          metas = Eval.walk_metas
          metas.fetch(key) { metas[key] = World.walk_meta(kind, name, owner, parent, file: @file, evaled: !@loaded, box: @box) }
        end

        # The frame of a call from the walked code at `line`, or nil.
        #: (Ctx ctx, Integer line) -> Array[untyped]?
        def frame_at(ctx, line) = ctx.meta && [ctx.meta, line, ctx.self_]

        # Runs `hir` in `ctx` and returns the value of its body. Code that
        # turns off CRuby's specialized instructions (Hir::Program#plain_new),
        # or that runs after the program turned them off, sends `new`, as
        # the compiled eval does (Eval::Compiler#plain_new?); else `new` is
        # opt_new.
        #: (Hir::Program hir, Ctx ctx) -> value
        def run(hir, ctx)
          @plain_new = hir.plain_new || specialized_off?
          walk(hir.body, ctx)
        end

        #: () -> bool
        def specialized_off?
          vm = Object.const_get(:RubyVM) #: untyped
          vm::InstructionSequence.compile_option[:specialized_instruction] == false
        end

        def walk(node, ctx)
          case node
          when nil then nil
          when Hir::Seq then node.stmts.map { |s| walk(s, ctx) }.last
          when Hir::Literal then literal(node)
          when Hir::PathLiteral then World.path(literal(node.literal))
          when Hir::FrozenString then frozen_string(node)
          when Hir::SelfRef then ctx.self_
          when Hir::Trace then trace(node, ctx)
          when Hir::Cover then World.coverage_branch(node.id)
          when Hir::Send then send_node(node, ctx)
          when Hir::Local then read_local(node, ctx)
          when Hir::Assign then write_local(node, walk(node.value, ctx), ctx)
          when Hir::If then truthy?(walk(node.cond, ctx)) ? walk(node.yes, ctx) : walk(node.no, ctx)
          when Hir::And then and_node(node, ctx)
          when Hir::Or then or_node(node, ctx)
          when Hir::Not then !truthy?(walk(node.value, ctx))
          when Hir::While then while_node(node, ctx)
          when Hir::ArrayLit then elements(node.elements, ctx)
          when Hir::HashLit then hash_lit(node.pairs, ctx)
          when Hir::KwSplatElement then kwsplat_element(node, ctx)
          when Hir::RangeLit then ::Range.new(walk(node.low, ctx), walk(node.high, ctx), node.exclusive)
          when Hir::Interp then interp(node, ctx)
          when Hir::RegexpLit then regexp(node)
          when Hir::IvarRead then ctx.self_.instance_variable_get(node.name)
          when Hir::IvarWrite then ivar_write(node, ctx)
          when Hir::GvarRead then gvar_read(node, ctx)
          when Hir::GvarWrite then gvar_write(node, ctx)
          when Hir::GvarAlias then World.gvar_alias(node.new_name, node.old_name)
          when Hir::CvarRead then World.cvar_get(ctx.cref, node.name)
          when Hir::CvarWrite then World.cvar_set(ctx.cref, node.name, walk(node.value, ctx))
          when Hir::ConstRead then const_read(node, ctx)
          when Hir::ConstWrite then const_write(node, walk(node.value, ctx), ctx)
          when Hir::ConstOrWrite then const_or_write(node, ctx)
          when Hir::Def then define(node, ctx)
          when Hir::ClassDef, Hir::ModuleDef then module_def(node, ctx)
          when Hir::SingletonClassDef then singleton_def(node, ctx)
          when Hir::Block then make_proc(node, ctx, lambda: false)
          when Hir::Lambda then make_proc(node.block, ctx, lambda: true)
          when Hir::Begin then begin_node(node, ctx)
          when Hir::Case then case_node(node, ctx)
          when Hir::MultiAssign then multi_assign(node, ctx)
          when Hir::Yield then yield_node(node, ctx)
          when Hir::Super then super_node(node, ctx)
          when Hir::ZSuper then zsuper_node(node, ctx)
          when Hir::Return then return_node(node, ctx)
          when Hir::Break then raise Breaking.new(walk(node.value, ctx), ctx.tag)
          when Hir::Next then raise Nexting.new(walk(node.value, ctx), ctx.tag)
          when Hir::Redo then raise Redoing.new(ctx.tag)
          when Hir::RedoPoint then nil
          when Hir::Retry then raise Retrying.new
          when Hir::Defined then defined_node(node, ctx)
          when Hir::IndexOpAssign then index_op_assign(node, ctx)
          when Hir::AttrOpAssign then attr_op_assign(node, ctx)
          when Hir::Alias then alias_node(ctx, node.new_name, node.old_name)
          when Hir::AliasValue then alias_node(ctx, walk(node.new_name, ctx), walk(node.old_name, ctx))
          when Hir::Undef then undef_node(ctx, node.names, node.line)
          when Hir::UndefValue then undef_node(ctx, node.names.map { |n| walk(n, ctx) }, node.line)
          when Hir::Core then ::Object.const_get(node.name)
          when Hir::Once then once(node, ctx)
          when Hir::Stop then raise ::NotImplementedError, "#{@file}:#{node.line}: #{node.what}"
          when Hir::ExtInit then raise ::NotImplementedError, "#{node.path}: a C extension runs only in a binary"
          when Hir::Require then require_node(node, ctx)
          when Hir::Autoload then autoload_node(node, ctx)
          when Hir::BackRef then backref(node, ctx)
          when Hir::RegexpOnce then regexps[node] ||= regexp_once(node.value, ctx)
          when Hir::Using, Hir::UsingDefaults then refuse(node, "using")
          else refuse(node, node.class.name.split("::").last)
          end
        end

        private

        # `return`. In a method that the string defines, it leaves that
        # method. Elsewhere it belongs to the frame that called eval: the
        # runtime returns from that frame's method, or from the file at the
        # top level, or raises LocalJumpError, as for compiled eval code.
        def return_node(node, ctx)
          value = walk(node.value, ctx)
          raise Returning.new(value, ctx.home) if ctx.home

          World.binding_return(@frame, value)
        end

        # A String literal is a new String each time, chilled as a literal
        # of the program is (`# frozen_string_literal` gives a
        # FrozenString node instead).
        def literal(node)
          value = node.value
          return value unless value.is_a?(::String)

          node.chilled ? World.chill(value.dup) : value.dup
        end

        # A frozen String literal, as the compiler gives it: the one
        # interned String of its text (`shared` true, nil and :uminus, with
        # a send of `freeze` or `-@` when the program redefines it), a
        # frozen String of its own for a text that is not UTF-8 (false), or
        # under debug_frozen_string_literal one that knows its file and line
        # (:debug). The last two are one object for the site.
        #: (Hir::FrozenString node) -> String
        def frozen_string(node)
          case node.shared
          when :debug then frozen_sites[node] ||= World.debug_string(node.value, @file, node.line)
          when false then frozen_sites[node] ||= World.frozen_string(node.value, 3)
          else World.frozen_string(node.value, { true => 0, nil => 1, uminus: 2 }.fetch(node.shared))
          end
        end

        # The String of each frozen literal site that has one of its own.
        #: () -> Hash[Hir::FrozenString, String]
        def frozen_sites
          @frozen ||= {}.compare_by_identity # steep:ignore UnannotatedEmptyCollection
        end

        # A Regexp literal is one frozen object for its site, as ruby
        # makes it once when it compiles the string. It is built as the
        # kernel's literal table builds it (Regexp.literal): a flag letter's
        # encoding pins the pattern, and the build already printed its
        # warnings.
        #: (Hir::RegexpLit node) -> Regexp
        def regexp(node)
          regexps[node] ||= begin
            pinned = node.pinned && ::Encoding.list.index(node.pinned)
            ::Regexp.__send__(:literal, node.source, node.options, pinned).freeze
          end
        end

        # The first value of a `/.../o` literal. The build runs its
        # interpolation in a block of its own, through the core's
        # Kernel.post_exe, which the walker calls in place.
        #: (Hir::node value, Ctx ctx) -> Regexp
        def regexp_once(value, ctx)
          block = value.block if value.is_a?(Hir::Send) && value.name == :post_exe && value.recv.is_a?(Hir::Core)
          block.is_a?(Hir::Block) ? make_proc(block, ctx, lambda: false).call : walk(value, ctx)
        end

        # The Regexp of each literal site that ran, by node.
        #: () -> Hash[Hir::RegexpLit | Hir::RegexpOnce, Regexp]
        def regexps
          @regexps ||= begin
            made = {} #: Hash[Hir::RegexpLit | Hir::RegexpOnce, Regexp]
            made.compare_by_identity
          end
        end

        # Only `false` and `nil` are false.
        def truthy?(value) = !value.nil? && value != false

        def refuse(node, what)
          raise Refused, "#{@file}:#{node.line}: #{what} is not walked yet"
        end

        # Locals. The chain is innermost first. The `depth` of a node is the
        # number of scopes out to the scope that contains the name, as the
        # front end resolved it.
        def read_local(node, ctx)
          scope = ctx.chain[node.depth] or return nil
          scope.get(node.name)
        end

        def write_local(node, value, ctx)
          scope = ctx.chain[node.depth] or return value
          scope.set(node.name, value)
          value
        end

        def ivar_write(node, ctx)
          value = walk(node.value, ctx)
          ctx.self_.instance_variable_set(node.name, value)
          value
        end

        # `$~` and `$_` belong to a frame, not to the global table: the
        # frame that called eval, or a method that the string defines. The
        # walk keeps them in that frame's cell (`svars`), which a send that
        # matches or reads a line fills (`svar_call`).
        FRAME_GLOBALS = { :$~ => 0, :$_ => 1 }.freeze

        # The `[$~, $_]` cell of the code that `ctx` runs.
        def svars(ctx) = ctx.svars || frame_svars

        # The cell of the frame that called eval.
        def frame_svars = @svars ||= World.binding_svars(@frame)

        def gvar_read(node, ctx)
          slot = FRAME_GLOBALS[node.name]
          return svars(ctx)[slot] if slot
          # The task's raise, which the walker's rescue set, as compiled
          # code reads it.
          return World.errinfo if node.name == :$!

          World.gvar_get(node.name)
        end

        def gvar_write(node, ctx)
          value = walk(node.value, ctx)
          slot = FRAME_GLOBALS[node.name]
          if slot
            raise ::TypeError, "wrong argument type #{value.class} (expected MatchData)" if slot.zero? && !value.nil? && !value.is_a?(::MatchData)

            svars(ctx)[slot] = value
          else
            World.gvar_set(node.shown || node.name, node.name, value)
          end
          value
        end

        # `$1`, `$&`, `` $` ``, `$'` and `$+`: a part of the last match.
        def backref(node, ctx)
          match = svars(ctx)[0] or return nil

          case node.kind
          when :nth then match[node.number]
          when :pre then match.pre_match
          when :post then match.post_match
          else (match.size - 1).downto(1).each { |i| return match[i] if match.begin(i) }
               nil
          end
        end

        # `autoload :Name, "feature"`: on the receiver, or on the module of
        # the lexical scope, as Kernel#autoload does.
        def autoload_node(node, ctx)
          owner = node.recv ? walk(node.recv, ctx) : World.cref_klass(ctx.cref)
          owner.autoload(node.name, node.feature)
        end

        # A `while` or `until`. Its value is nil, or the value of a `break`.
        def and_node(node, ctx)
          left = walk(node.left, ctx)
          truthy?(left) ? walk(node.right, ctx) : left
        end

        def or_node(node, ctx)
          left = walk(node.left, ctx)
          truthy?(left) ? left : walk(node.right, ctx)
        end

        def while_node(node, ctx)
          tag = node.__id__
          inner = ctx.with(tag: tag)
          first = node.body_first
          while first || truthy?(walk(node.cond, ctx))
            first = false
            begin
              walk(node.body, inner)
            rescue Nexting => e
              raise unless e.tag.equal?(tag)
            rescue Redoing => e
              raise unless e.tag.equal?(tag)

              retry
            end
          end
          nil
        rescue Breaking => e
          raise unless e.tag.equal?(tag)

          e.value
        end

        # An array literal, or the positional arguments of a call. A
        # `*splat` spreads in its position.
        #: (Array[Hir::node] nodes, Ctx ctx) -> Array[value]
        def elements(nodes, ctx)
          out = [] #: Array[value]
          nodes.each do |n|
            if n.is_a?(Hir::Splat)
              value = walk(n.value, ctx)
              out.concat(splat_array(value))
            else
              out << walk(n, ctx)
            end
          end
          out
        end

        # `*value` as ruby spreads it: an Array as is, nil as no elements,
        # an object with `to_a` through `to_a`, else as one element.
        def splat_array(value)
          return value if value.is_a?(::Array)
          return [] if value.nil?
          return value.to_a if value.respond_to?(:to_a)

          [value]
        end

        # `{k => v, **h}`: the pairs are flat, key then value. A double
        # splat is a key with a nil value.
        #: (Array[Hir::node?] pairs, Ctx ctx) -> Hash[value, value]
        def hash_lit(pairs, ctx)
          out = {} #: Hash[value, value]
          i = 0
          while i < pairs.size
            key = pairs[i]
            if key.is_a?(Hir::HashSplat)
              spread = walk(key.value, ctx)
              out.update(spread.to_hash) unless spread.nil?
              i += 2
            else
              out[walk(key, ctx)] = walk(pairs[i + 1], ctx)
              i += 2
            end
          end
          out
        end

        # `[**h]`: the pairs as one Array element, or no element when the
        # hash is empty.
        def kwsplat_element(node, ctx)
          h = hash_lit(node.pairs.pairs, ctx)
          h.empty? ? [] : [h]
        end

        def interp(node, ctx)
          if node.held
            value = walk(node.parts.first, ctx)
            return value.is_a?(::String) ? value : stringify(value)
          end

          out = +""
          node.parts.each do |part|
            value = walk(part, ctx)
            out << (value.is_a?(::String) ? value : stringify(value))
          end
          out
        end

        # The text of `"#{x}"`: `to_s`, or `inspect` when `to_s` does not
        # return a String, as CRuby's rb_obj_as_string does.
        def stringify(value)
          said = value.to_s
          said.is_a?(::String) ? said : value.inspect
        end

        # Constants. The lookup is the kernel's, so a name in the string
        # finds the same constant as compiled code in the same scope.
        def const_read(node, ctx)
          return World.const_get_at(::Object, node.name) if node.scope == :top

          if node.scope
            scope = walk(node.scope, ctx)
            # Hir::ConstRead#nil_lexical: a nil scope reads lexically.
            return World.const_get_at(scope, node.name) unless scope.nil? && node.nil_lexical
          end
          World.const_get(ctx.cref, node.name)
        end

        def const_write(node, value, ctx)
          # Steep finds Module#const_set on World before World#const_set.
          World.const_set(const_base(node, ctx), node.name, value, frame_at(ctx, node.line)) # steep:ignore UnexpectedPositionalArgument
          value
        end

        def const_or_write(node, ctx)
          return const_read(node, ctx) if const_defined?(node, ctx)

          const_write(node, walk(node.value, ctx), ctx)
        end

        def const_defined?(node, ctx)
          return World.const_defined_at?(::Object, node.name) if node.scope == :top
          return World.const_defined_at?(walk(node.scope, ctx), node.name) if node.scope

          World.const_defined?(ctx.cref, node.name)
        end

        # The scope of a constant write: the scope before `::`, else the
        # innermost lexical scope. The cref of the eval itself is not a
        # lexical scope.
        def const_base(node, ctx)
          return ::Object if node.scope == :top
          return walk(node.scope, ctx) if node.scope

          World.cref_klass(World.cref_lexical(ctx.cref))
        end

        # Methods that read the frame of their caller. The interpreter runs
        # in frames of its own files, not of the string, so a usual call
        # would return data for `tree.rb`. `frame_method` returns what the
        # context knows (FROM_THE_FRAME). The rest (NO_FRAME) read the
        # frame that the call runs under (`frame_at`), and are refused
        # where the world pushes none.
        FROM_THE_FRAME = %i[block_given? iterator? __method__ __callee__ local_variables binding __dir__].freeze
        NO_FRAME = %i[caller caller_locations].freeze

        # The words that set the default visibility of a body. It is in
        # the cref, not in a frame. Without arguments, they change the
        # visibility of the next `def`s. With names, they are usual calls.
        VISIBILITY = { private: 1, public: 0, protected: 2 }.freeze

        # A call with more arguments than this checks that ruby's VM stack
        # would hold them, as a compiled call does (Lower's MANY_ARGS).
        MANY_ARGS = 1_024

        def send_node(node, ctx)
          refuse(node, "a call under a refinement") if node.using
          return frame_method(node, ctx) if bare?(node) && (FROM_THE_FRAME.include?(node.name) || (NO_FRAME.include?(node.name) && !ctx.meta))
          return body_visibility(node, ctx) if bare?(node) && (VISIBILITY.key?(node.name) || node.name == :module_function)
          recv = node.recv ? walk(node.recv, ctx) : ctx.self_
          return World.nesting(ctx.cref) if node.name == :nesting && recv.equal?(::Module) && node.args.empty? && node.block.nil?
          cover_safe(node, recv) if node.covers
          return nil if node.safe && recv.nil?
          return recv if node.interp && (String === recv || Symbol === recv)

          World.vm_stack_args(node.args.size) if node.args.size > MANY_ARGS
          args = elements(node.args, ctx)
          kwargs = node.kwargs ? hash_lit(node.kwargs.pairs, ctx) : nil
          block = block_for(node.block, ctx)
          call(recv, node.name, args, kwargs, block, private: private_call?(node), at: frame_at(ctx, node.line), vcall: node.vcall,
                                                     breaks: node.block.is_a?(Hir::Block) && node.block,
                                                     svars: (svars(ctx) if svar_send?(recv, node.name)))
        end

        # The core methods that set or read their caller's `$~` or `$_`. In
        # ruby they are C functions, which see the frame of their caller.
        # Most are methods of String, Symbol and Regexp, so an Array's `[]`
        # does not pay for them; a line read and `print` go to any receiver.
        TEXT_SVAR_SENDS = %i[=~ !~ === ~ match scan sub sub! gsub gsub! index rindex byteindex byterindex [] slice slice!
                             start_with? partition rpartition last_match].to_set.freeze
        LINE_SVAR_SENDS = %i[gets readline print].to_set.freeze

        def svar_send?(recv, name)
          return true if LINE_SVAR_SENDS.include?(name)

          TEXT_SVAR_SENDS.include?(name) && (::String === recv || ::Symbol === recv || ::Regexp === recv || recv.equal?(::Regexp))
        end

        # A call can reach a private method when it has no receiver or its
        # receiver is the literal `self`, as in ruby.
        def private_call?(node) = node.recv.nil? || node.recv.is_a?(Hir::SelfRef)

        # A call written as a bare name, with no arguments and no block.
        def bare?(node) = node.recv.nil? && node.args.empty? && node.kwargs.nil? && node.block.nil?

        def frame_method(node, ctx)
          case node.name
          when :block_given?, :iterator? then !ctx.block.nil?
          # Outside a method of the string, the method of the frame that
          # the eval reads (`bm = binding; bm.eval("__method__")`).
          when :__method__, :__callee__ then ctx.name || World.binding_method(@frame)&.first
          when :local_variables then ctx.chain.flat_map(&:names).uniq
          when :binding then scope_binding(ctx)
          when :__dir__ then @file.start_with?("(eval") ? nil : ::File.dirname(@file)
          else refuse(node, node.name.to_s)
          end
        end

        # `binding` in the string: the caller's Binding, with the locals
        # that the string's own scopes hold. In a method or a body that the
        # string defines, or under another self, it is a new Binding of
        # that self with only the string's locals. It copies their values:
        # a later write in the string does not reach it.
        def scope_binding(ctx)
          caller = ctx.chain.any?(Held) && World.same?(ctx.self_, @frame.receiver)
          scope = caller ? @frame.dup : World.bare_binding(ctx.self_)
          ctx.chain.each do |held|
            next if caller && held.is_a?(Held)

            held.names.each { |name| scope.local_variable_set(name, held.get(name)) unless scope.local_variable_defined?(name) }
          end
          scope
        end

        def body_visibility(node, ctx)
          node.name == :module_function ? World.set_module_function(ctx.cref) : World.set_vis(ctx.cref, VISIBILITY.fetch(node.name))
          nil
        end

        def block_for(node, ctx)
          case node
          when nil then nil
          when Hir::Block then make_proc(node, ctx, lambda: false)
          when Hir::BlockPass then block_pass(walk(node.value, ctx))
          else walk(node, ctx)
          end
        end

        # `&value`: nil passes no block, a Proc passes itself, and other
        # objects (a Symbol too) go through `to_proc`.
        def block_pass(value)
          return nil if value.nil?
          return value if value.is_a?(::Proc)

          value.to_proc
        end

        # One send. `vcall` marks a bare identifier: if no method is found,
        # the error is a NameError, not a NoMethodError. `breaks` is the
        # block literal of this call; a `break` in it returns from this call.
        # @rbs recv: value
        # @rbs name: Symbol
        # @rbs args: Array[value]
        # @rbs kwargs: Hash[Symbol, value]?
        # @rbs block: Proc?
        # @rbs private: bool
        # @rbs vcall: bool
        # @rbs breaks: Hir::Block | false | nil
        # @rbs svars: svars?
        # @rbs at: Array[untyped]?
        # @rbs return: value
        def call(recv, name, args, kwargs, block, private:, at: nil, vcall: false, breaks: nil, svars: nil)
          tag = breaks && breaks.__id__
          if svars
            svar_send(recv, name, args, kwargs, block, private, svars)
          else
            World.walk_send(at, recv, name, args, kwargs: kwargs.nil? || kwargs.empty? ? nil : kwargs, blk: block, private: private, vcall: vcall,
                                                  new: name == :new && !@plain_new)
          end
        rescue Breaking => e
          raise unless tag && e.tag.equal?(tag)

          e.value
        rescue ::NoMethodError => e
          raise unless vcall && e.name == name && e.receiver.equal?(recv)

          # Ruby keeps the Symbol as NameError#name; RBS types it as a String.
          raise ::NameError.new("undefined local variable or method '#{name}' for #{recv.inspect}", name, receiver: recv) # steep:ignore ArgumentTypeMismatch
        end

        # A send that `svar_send?` picks. The method sets and reads the `$~`
        # and `$_` of this frame, so the frame takes them from the walked
        # code's cell first and gives them back after. A block sees each
        # match that the method makes before it yields (`gsub { $1 }`).
        #: (value recv, Symbol name, Array[value] args, Hash[Symbol, value]? kwargs, Proc? block, bool private, svars cell) -> value
        def svar_send(recv, name, args, kwargs, block, private, cell)
          $~ = cell[0]
          $_ = cell[1]
          if block
            inner = block
            # The method gives the arguments, so Steep cannot type them.
            block = proc do |*values, **options, &passed|
              cell[0] = $~
              cell[1] = $_
              inner.call(*values, **options, &passed) # steep:ignore
            end
          end
          if kwargs.nil? || kwargs.empty?
            private ? recv.__send__(name, *args, &block) : recv.public_send(name, *args, &block)
          else
            private ? recv.__send__(name, *args, **kwargs, &block) : recv.public_send(name, *args, **kwargs, &block)
          end
        ensure
          cell[0] = $~
          cell[1] = $_
        end

        # Blocks. A block is a Proc whose body the interpreter walks.
        # `break`, `next` and `redo` in it raise the unwind exceptions above,
        # and the call that got the block catches a `break`.
        # `home` is the lexical scope of all frames of this file. If a block
        # runs under a different scope, `class_eval`, `instance_eval`,
        # `class_exec` or `instance_exec` called it with a different self
        # and definee. Compiled code can do this to an interpreted block:
        # `Forwardable` evaluates a string to a proc and gives it to
        # `module_eval`. The interpreter then uses that self and scope.
        #: (Hir::Block node, Ctx ctx, lambda: bool) -> Proc
        def make_proc(node, ctx, lambda:)
          tree = self
          home = World.cref
          # Only the literal makes a lambda: `Kernel#lambda` refuses a Proc
          # that is not its literal block. The program gives the arguments,
          # so Steep cannot type them.
          made = if lambda
                   ->(*args, **kwargs, &blk) { tree.__send__(:run_block, node, ctx, args, kwargs, blk, lambda: true, home: home, here: World.cref, self_: self) } # steep:ignore FallbackAny
                 else
                   proc { |*args, **kwargs, &blk| tree.__send__(:run_block, node, ctx, args, kwargs, blk, lambda: false, home: home, here: World.cref, self_: self) } # steep:ignore FallbackAny
                 end
          spanned(made, node.span)
        end

        # `proc` with the span of the walked code that it runs (World.walk_span),
        # for its source_location and source_range.
        #: (Proc proc, Array[Integer]? span) -> Proc
        def spanned(proc, span)
          World.walk_span(proc, [@file, @loaded, *span, 0]) if span
          proc
        end

        # `home` and `here` are crefs (`World.cref`).
        # @rbs node: Hir::Block
        # @rbs ctx: Ctx
        # @rbs args: Array[value]
        # @rbs kwargs: Hash[Symbol, value]?
        # @rbs blk: Proc?
        # @rbs lambda: bool
        # @rbs home: cref
        # @rbs here: cref
        # @rbs self_: value
        # @rbs return: value
        def run_block(node, ctx, args, kwargs, blk, lambda:, home: nil, here: nil, self_: nil)
          # The ensure reads these, so they have their types there too.
          # @type var outer: untyped
          # @type var inner: Ctx
          # @type var value: value
          outer = World.walk_enter(@box)
          ctx = ctx.with(self_: self_, cref: World.walk_cref(here, ctx.cref), name: nil, owner: nil, home: nil) if here && !World.same?(here, home)
          tag = node.__id__
          scope = Scope.new(node.locals)
          # A `yield` in a block calls the block of the method that
          # contains the block. A block passed to the block itself is only
          # in its `&blk` parameter.
          inner = ctx.with(chain: [scope, *ctx.chain], tag: tag, meta: scope_meta(:block, nil, nil, ctx.meta))
          bind(node.params, scope, args, kwargs, blk, inner, strict: lambda, spread: !lambda)
          fire(:b_call, inner, node.line, lambda: lambda)
          value = nil
          value = begin
            walk(node.body, inner)
          rescue Nexting => e
            raise unless e.tag.equal?(tag)

            e.value
          rescue Redoing => e
            raise unless e.tag.equal?(tag)

            retry
          end
        ensure
          fire(:b_return, inner, node.end_line || node.line, value, lambda: lambda) if inner
          World.walk_leave(outer)
        end

        # Method definition. Each call walks the body, in the lexical scope
        # of the `def`.
        def define(node, ctx)
          owner = node.receiver ? World.singleton_of(walk(node.receiver, ctx)) : World.cref_definee(ctx.cref)
          tree = self
          cref = ctx.cref
          # The program gives the arguments, so Steep cannot type them.
          body = spanned(proc do |*args, **kwargs, &blk|
            tree.__send__(:run_method, node, self, owner, cref, args, kwargs, blk) # steep:ignore FallbackAny
          end, node.span)
          # Under the walked code's frame, so a warning of the definition
          # (a redefined core method) names its line.
          call(owner, :define_method, [node.name], nil, body, private: true, at: frame_at(ctx, node.line))
          World.walk_signature(owner.instance_method(node.name), node.params.rows, node.params.arity)
          # Coverage's record of the method, at the def's site.
          World.coverage_claim(owner, node.name, node.cover) if node.cover
          visibility(owner, node, cref) unless node.receiver
          node.name
        end

        # Applies to a `def` in `cref` the current default visibility of the
        # body, and the singleton copy that `module_function` makes.
        def visibility(owner, node, cref)
          if World.module_function?(cref)
            owner.singleton_class.send(:define_method, node.name, owner.instance_method(node.name))
            World.coverage_claim(owner.singleton_class, node.name, node.cover) if node.cover
          end
          case World.definition_vis(node.name, cref)
          when 1 then owner.send(:private, node.name)
          when 2 then owner.send(:protected, node.name)
          end
        end

        # A method or a block that the walk made can run after the eval
        # that made it returned, when compiled code calls it (rubygems'
        # Kernel#require, which rubygems evals). While it runs, the program
        # is the caller of the runtime, as in `Interpreter.evaluate`
        # (`World.walk_enter`): a constant that it defines on Object and a
        # file that it requires are the program's, not hidden.
        def run_method(node, self_, owner, cref, args, kwargs, blk)
          # @type var outer: untyped
          # @type var ctx: Ctx
          # @type var value: value
          outer = World.walk_enter(@box)
          tag = node.__id__
          scope = Scope.new(node.locals)
          ctx = Ctx.new(self_: self_, cref: cref, chain: [scope], block: blk,
                        name: node.name, owner: owner, args: args, kwargs: kwargs, tag: tag, home: tag, svars: [nil, nil],
                        meta: scope_meta(:def, node.name, owner, nil))
          bind(node.params, scope, args, kwargs, blk, ctx, strict: true, spread: false)
          fire(:call, ctx, node.line)
          value = nil
          value = begin
            walk(node.body, ctx)
          rescue Returning => e
            raise unless e.tag.equal?(tag)

            e.value
          end
        ensure
          fire(:return, ctx, node.end_line || node.line, value) if ctx
          World.walk_leave(outer)
        end

        def module_def(node, ctx)
          base = if node.scope == :top then ::Object
                 elsif node.scope then walk(node.scope, ctx)
                 else World.cref_klass(World.cref_lexical(ctx.cref))
                 end
          # The kernel opens or defines it as compiled code does: a new
          # class has its name before the superclass's `inherited` runs.
          scoped = !node.scope.nil?
          mod = if node.is_a?(Hir::ClassDef)
                  sup = node.superclass && walk(node.superclass, ctx)
                  World.class_define(frame_at(ctx, node.line), base, node.name, sup, !node.superclass.nil?, scoped)
                else
                  World.module_define(frame_at(ctx, node.line), base, node.name, scoped)
                end
          run_body(node, mod, ctx)
        end

        def singleton_def(node, ctx) = run_body(node, World.singleton_of(walk(node.target, ctx)), ctx)

        # A class, module or singleton class body: its own scope, its own
        # self, and a lexical scope one level inside the enclosing scope.
        def run_body(node, mod, ctx)
          kind = case node
                 when Hir::ClassDef then :class
                 when Hir::ModuleDef then :module
                 else :sclass
                 end
          meta = scope_meta(kind, kind == :sclass ? nil : node.name, nil, nil)
          inner = Ctx.new(self_: mod, cref: World.cref_push(mod, ctx.cref), chain: [Scope.new(node.locals)],
                          block: nil, name: nil, owner: nil, args: nil, kwargs: nil, tag: node.__id__, home: nil, svars: [nil, nil], meta: meta)
          # A `class << obj` body fires neither :class nor :end, as in ruby.
          return walk(node.body, inner) if kind == :sclass

          fire(:class, inner, node.line)
          begin
            walk(node.body, inner)
          ensure
            fire(:end, inner, node.end_line || node.line)
          end
        end

        # `begin ... rescue ... else ... ensure ... end`.
        def begin_node(node, ctx)
          # `retry` runs the protected body again, not the rescue clause,
          # so the code catches it outside both.
          begin
            value = nil
            begin
              value = walk(node.body, ctx)
              value = walk(node.else_body, ctx) if node.else_body
            rescue Signal
              raise
            rescue ::Exception => e # rubocop:disable Lint/RescueException
              clause = node.rescues.find { |r| catches?(r, e, ctx) } or raise
              write_target(clause.target, e, ctx) if clause.target
              value = walk(clause.body, rescue_ctx(ctx, node.line))
            end
            value
          rescue Retrying
            retry
          end
        ensure
          walk(node.ensure_body, ctx) if node.ensure_body
        end

        # The context of a rescue clause of the `begin` at `line`: CRuby runs
        # the clause in a frame of its own, which a caller list counts
        # (World.rescue_meta).
        #: (Ctx ctx, Integer line) -> Ctx
        def rescue_ctx(ctx, line)
          meta = ctx.meta or return ctx

          metas = Eval.walk_metas
          ctx.with(meta: metas.fetch([:rescue, meta, line]) { metas[[:rescue, meta, line]] = World.rescue_meta(meta, line) })
        end

        def catches?(clause, error, ctx)
          return ::StandardError === error if clause.classes.empty?

          elements(clause.classes, ctx).any? { |k| k === error }
        end

        def case_node(node, ctx)
          refuse(node, "a case under a refinement") if node.subject && node.using
          subject = node.subject ? [walk(node.subject, ctx)] : nil
          node.clauses.each do |values, body|
            return walk(body, ctx) if values.any? { |v| matches?(v, subject, ctx) }
          end
          walk(node.else_body, ctx)
        end

        # Tests one `when` value against the subject, or tests its truth
        # when the `case` has no subject. A `*splat` tests each element.
        # `===` is a send, so a program's own `===` answers, as in ruby.
        def matches?(value, subject, ctx)
          at = frame_at(ctx, value.line)
          if value.is_a?(Hir::Splat)
            return splat_array(walk(value.value, ctx)).any? { |v| truthy?(subject ? case_eq(v, subject.first, at) : v) }
          end
          v = walk(value, ctx)
          return truthy?(v) unless subject
          return truthy?(svar_send(v, :===, [subject.first], nil, nil, false, svars(ctx))) if v.is_a?(::Regexp)

          truthy?(case_eq(v, subject.first, at))
        end

        #: (value pattern, value subject, Array[untyped]? at) -> value
        def case_eq(pattern, subject, at) = call(pattern, :===, [subject], nil, nil, private: false, at: at)

        # A line event counts for Coverage, as compiled code's does;
        # TracePoint hears no walked code. The event of an ensure body that
        # compiles to nothing waits for the path that runs the body, which
        # the walk does not follow, so it counts no line.
        # A :line or :branch_jump event: one run of its line, in the
        # Coverage row of this walk. The walk takes a row of its own, as
        # each compiled file and eval has one, once Coverage is set up: a
        # row that Coverage measures for a loaded file, and for an eval
        # under `eval: true`.
        # A :line event fires the TracePoints that listen, as compiled code's
        # does.
        #: (Hir::Trace node, Ctx ctx) -> nil
        def trace(node, ctx)
          return nil unless node.event == :line || node.event == :branch_jump

          @coverage_row ||= World.coverage_begin(@file, @loaded)
          World.coverage_line(@coverage_row, node.line, node.event == :branch_jump) if @coverage_row
          fire(:line, ctx, node.line) if node.event == :line
          nil
        end

        # ruby's RUBY_EVENT_* bits (Lower::Function::Tracing::EVENTS), and
        # the bit of a lambda's block events (the kernel's TRACE_LAMBDA).
        EVENTS = { line: 0x1, class: 0x2, end: 0x4, call: 0x8, return: 0x10, b_call: 0x100, b_return: 0x200 }.freeze
        LAMBDA = 1 << 32

        # Fires `event` of the walked scope of `ctx` at `line`, with a
        # closing event's `value`, as the compiler's Tracing does.
        #: (Symbol event, Ctx ctx, Integer? line, ?untyped value, ?lambda: bool) -> untyped
        def fire(event, ctx, line, value = nil, lambda: false)
          return value unless ctx.meta && line

          World.walk_trace(frame_at(ctx, line), EVENTS.fetch(event) | (lambda ? LAMBDA : 0), value)
        end

        # The branch of a safe call (`recv&.name`) that Coverage counts: the
        # call, or for a nil receiver the nil one. `self&.x` counts the
        # call, as the compiler's does (Function#safe_call).
        #: (Hir::Send node, untyped recv) -> void
        def cover_safe(node, recv)
          covers = node.covers or return
          World.coverage_branch((recv.nil? && !node.recv.is_a?(Hir::SelfRef) ? covers.last : covers.first).id)
        end

        # `a, (b, *c), *d, e = value`.
        # The receivers and arguments of its send targets, and the scopes
        # of its constants, are evaluated left to right before the value,
        # as the compiler stages them.
        def multi_assign(node, ctx)
          prepared = {} #: Hash[Hir::node, untyped]
          prepared.compare_by_identity
          prepare(node.target, prepared, ctx)
          value = walk(node.value, ctx)
          spread(node.target, splat_array(value), ctx, prepared)
          value
        end

        #: (Hir::node | :implicit | nil target, Hash[Hir::node, untyped] prepared, Ctx ctx) -> void
        def prepare(target, prepared, ctx)
          case target
          when Hir::MultiTarget
            target.lefts.each { |t| prepare(t, prepared, ctx) }
            prepare(target.rest, prepared, ctx)
            target.rights.each { |t| prepare(t, prepared, ctx) }
          when Hir::Send then prepared[target] = send_parts(target, ctx)
          when Hir::ConstWrite then prepared[target] = const_base(target, ctx)
          end
        end

        #: (Hir::MultiTarget target, Array[value] values, Ctx ctx, ?Hash[Hir::node, untyped]? prepared) -> Array[value]
        def spread(target, values, ctx, prepared = nil)
          values = values.dup
          target.lefts.each { |t| write_target(t, values.shift, ctx, prepared) }
          rest = target.rest
          if rest
            take = values.size - target.rights.size
            taken = [] #: Array[value]
            taken = values.shift(take) if take.positive?
            write_target(rest, taken, ctx, prepared) unless rest == :implicit
          end
          target.rights.each { |t| write_target(t, values.shift, ctx, prepared) }
          values
        end

        # One target of a multiple assignment, of a rescue `=> e`, or of a
        # destructuring parameter: a local, a variable, a constant, a
        # `h[k]` or an attribute, or a nested target.
        def write_target(target, value, ctx, prepared = nil)
          case target
          when Hir::Assign then write_local(target, value, ctx)
          when Hir::IvarWrite then ctx.self_.instance_variable_set(target.name, value)
          when Hir::GvarWrite then World.gvar_set(target.shown || target.name, target.name, value)
          when Hir::CvarWrite then World.cvar_set(ctx.cref, target.name, value)
          # Steep finds Module#const_set on World before World#const_set.
          when Hir::ConstWrite
            World.const_set(prepared&.fetch(target, nil) || const_base(target, ctx), target.name, value, frame_at(ctx, target.line)) # steep:ignore UnexpectedPositionalArgument
          when Hir::MultiTarget then spread(target, splat_array(value), ctx, prepared)
          when Hir::Send then write_send(target, value, ctx, prepared&.fetch(target, nil))
          else refuse(target, "#{target.class.name.split("::").last} as an assignment target")
          end
        end

        def write_send(target, value, ctx, parts = nil)
          recv, args = parts || send_parts(target, ctx)
          # `o&.x = v` writes nothing when `o` is nil.
          return value if target.safe && recv.nil?

          call(recv, target.name, args + [value], nil, nil, private: private_call?(target), at: frame_at(ctx, target.line))
          value
        end

        # The receiver and the arguments of a send target.
        def send_parts(target, ctx) = [target.recv ? walk(target.recv, ctx) : ctx.self_, elements(target.args, ctx)]

        # A require that the build found the file of: the program's own
        # require, load or require_relative runs at run time with the
        # file's path, as the compiled require runs the file's unit.
        def require_node(node, ctx)
          # Eval support's own require runs the file that the program
          # carries, hidden from the program, as compiled code's does, by
          # the path that the build wrote (Function#require_unit).
          return World.require_hidden(Paths.shown(node.path)) if node.kind == :hidden

          name = node.kind == :load ? :load : :require
          call(ctx.self_, name, [node.path], nil, nil, private: true, at: frame_at(ctx, node.line))
        end

        def yield_node(node, ctx)
          block = ctx.block or raise ::LocalJumpError, "no block given (yield)"
          args = elements(node.args, ctx)
          kwargs = node.kwargs ? hash_lit(node.kwargs.pairs, ctx) : nil #: Hash[Symbol, value]?
          World.walk_yield(frame_at(ctx, node.line), block, args, kwargs.nil? || kwargs.empty? ? nil : kwargs)
        end

        # `super(args)` and the bare `super`, which passes the arguments of
        # the method again. The target is the next module after the owner
        # of the method in the ancestors of the receiver, as in the lookup
        # of the runtime.
        def super_node(node, ctx)
          args = elements(node.args, ctx)
          kwargs = node.kwargs ? hash_lit(node.kwargs.pairs, ctx) : nil
          call_super(ctx, args, kwargs, block_for(node.block, ctx) || ctx.block)
        end

        def zsuper_node(node, ctx)
          call_super(ctx, ctx.args || [], ctx.kwargs, block_for(node.block, ctx) || ctx.block)
        end

        # In a method that the string defines, `super` starts after that
        # method's owner. Elsewhere it belongs to the method of the frame
        # that called eval.
        #: (Ctx ctx, Array[value] args, Hash[Symbol, value]? kwargs, (^(*value) -> value)? block) -> value
        def call_super(ctx, args, kwargs, block)
          name, owner = super_of(ctx)
          raise ::NoMethodError, "super called outside of method" unless name && owner

          method = super_method(ctx.self_, name, owner) or
            # Ruby keeps the Symbol as NameError#name; RBS types it as a String.
            raise ::NoMethodError.new("super: no superclass method '#{name}' for #{receiver_text(ctx.self_)}", name, receiver: ctx.self_) # steep:ignore ArgumentTypeMismatch
          if kwargs.nil? || kwargs.empty?
            method.bind_call(ctx.self_, *args, &block)
          else
            method.bind_call(ctx.self_, *args, **kwargs, &block)
          end
        end

        # The receiver as ruby's NoMethodError message names it.
        def receiver_text(obj)
          case obj
          when nil, true, false then obj.inspect
          when ::Module then "#{obj.is_a?(::Class) ? "class" : "module"} #{obj.inspect}"
          else obj.equal?(::TOPLEVEL_BINDING.receiver) ? "main" : "an instance of #{obj.class}"
          end
        end

        # The name and the owner that `super` starts from, or nil.
        #: (Ctx ctx) -> [Symbol, Module]?
        def super_of(ctx)
          return [ctx.name, ctx.owner] if ctx.name && ctx.owner

          World.binding_method(@frame)
        end

        # The next method `name` after `owner` in the ancestors of `self_`,
        # or nil.
        #: (value self_, Symbol name, Module owner) -> UnboundMethod?
        def super_method(self_, name, owner)
          chain = self_.class.ancestors
          chain = self_.singleton_class.ancestors if self_.singleton_class.ancestors.include?(owner)
          at = chain.index(owner) or return nil
          found = chain[(at + 1)..]&.find { |m| m.method_defined?(name, false) || m.private_method_defined?(name, false) }
          found&.instance_method(name)
        end

        # `defined?(...)`: the same string that ruby returns, or nil.
        def defined_node(node, ctx)
          case node.kind
          when :self then "self"
          when :nil then "expression"
          when :true then "expression"
          when :false then "expression"
          when :assignment then "assignment"
          when :yield then ctx.block ? "yield" : nil
          # The parser makes a name a local only where it is one, so the
          # node has no target to look up (`Hir::Build#defined`).
          when :local then "local-variable"
          when :ivar then ctx.self_.instance_variable_defined?(node.target) ? "instance-variable" : nil
          when :gvar then truthy?(World.gvar_defined?(node.target)) ? "global-variable" : nil
          when :cvar then truthy?(World.cvar_defined?(ctx.cref, node.target)) ? "class variable" : nil
          when :const then defined_const(node, ctx)
          when :method then defined_method(node, ctx)
          when :attrasgn then defined_method(node, ctx)
          # All other forms are expressions: `defined?` does not run them.
          when :expression then "expression"
          when :global then "global-variable"
          when :backref then walk(node.target, ctx).nil? ? nil : "global-variable"
          when :super then defined_super(ctx)
          when :list then node.target.all? { |part| part_defined?(part, ctx) } ? "expression" : nil
          else refuse(node, "defined?(#{node.kind})")
          end
        end

        # Whether a part of an Array or Hash literal is defined, as the
        # compiler's part_defined tests it: a name by its form, any other
        # expression is.
        def part_defined?(part, ctx)
          case part
          when Hir::Send then !defined_method(Hir::Defined.new(:method, part, part.line), ctx).nil?
          when Hir::Splat then part_defined?(part.value, ctx)
          when Hir::ArrayLit then part.elements.all? { |element| part_defined?(element, ctx) }
          when Hir::HashLit then part.pairs.compact.all? { |pair| part_defined?(pair.is_a?(Hir::HashSplat) ? pair.value : pair, ctx) }
          when Hir::ConstRead then !defined_const(Hir::Defined.new(:const, part, part.line), ctx).nil?
          when Hir::IvarRead then ctx.self_.instance_variable_defined?(part.name)
          when Hir::GvarRead then truthy?(World.gvar_defined?(part.name))
          when Hir::CvarRead then truthy?(World.cvar_defined?(ctx.cref, part.name))
          else true
          end
        end

        def defined_const(node, ctx)
          truthy?(const_defined?(node.target, ctx)) ? "constant" : nil
        rescue ::StandardError
          nil
        end

        def defined_method(node, ctx)
          send = node.target
          recv = send.recv ? walk(send.recv, ctx) : ctx.self_
          return "method" if private_call?(send) ? recv.respond_to?(send.name, true) : recv.respond_to?(send.name)

          nil
        rescue ::StandardError
          nil
        end

        def defined_super(ctx)
          name, owner = super_of(ctx)
          name && owner && super_method(ctx.self_, name, owner) ? "super" : nil
        end

        # `recv[args] op= value` and `recv.name op= value`: the receiver
        # and the arguments are evaluated only once.
        def index_op_assign(node, ctx)
          recv = walk(node.recv, ctx)
          args = elements(node.args, ctx)
          current = recv.public_send(:[], *args)
          return current if short_circuit?(node.op, current)

          value = combined(node.op, current, node.value, ctx)
          recv.public_send(:[]=, *args, value)
          value
        end

        def attr_op_assign(node, ctx)
          recv = walk(node.recv, ctx)
          return nil if node.safe && recv.nil?

          none = [] #: Array[value]
          current = call(recv, node.name, none, nil, nil, private: private_call?(node), at: frame_at(ctx, node.line))
          return current if short_circuit?(node.op, current)

          value = combined(node.op, current, node.value, ctx)
          call(recv, :"#{node.name}=", [value], nil, nil, private: private_call?(node), at: frame_at(ctx, node.line))
          value
        end

        def short_circuit?(op, current) = (op == :or && truthy?(current)) || (op == :and && !truthy?(current))

        def combined(op, current, value_node, ctx)
          return walk(value_node, ctx) if op == :or || op == :and

          current.public_send(op, walk(value_node, ctx))
        end

        def alias_node(ctx, new_name, old_name)
          # Steep finds Module#alias_method on World before World#alias_method.
          World.alias_method(World.cref_definee(ctx.cref), new_name.to_sym, old_name.to_sym) # steep:ignore UnexpectedPositionalArgument
          nil
        end

        # Each undef runs under the walked code's frame, so a warning of it
        # (a core method's) names its line.
        def undef_node(ctx, names, line)
          mod = World.cref_definee(ctx.cref)
          names.each { |name| call(mod, :undef_method, [name.to_sym], nil, nil, private: true, at: frame_at(ctx, line)) }
          nil
        end

        # `END { }`: the body runs only the first time that execution gets
        # to the site.
        #: (Hir::Once node, Ctx ctx) -> value
        def once(node, ctx)
          once = @once ||= begin
            seen = {} #: Hash[Hir::Once, value]
            seen.compare_by_identity
          end
          return once[node] if once.key?(node)

          once[node] = walk(node.body, ctx)
        end

        # Parameters. `args` are the positional arguments, and `kwargs` are
        # the keywords or nil. `strict` turns on the arity check: a method
        # and a lambda do it, a block does not.
        # @rbs params: Hir::Params
        # @rbs scope: Scope
        # @rbs args: Array[value]
        # @rbs kwargs: Hash[Symbol, value]?
        # @rbs blk: Proc?
        # @rbs ctx: Ctx
        # @rbs strict: bool
        # @rbs spread: bool
        # @rbs return: void
        def bind(params, scope, args, kwargs, blk, ctx, strict:, spread:)
          args = args.dup
          kwargs = nil if kwargs && kwargs.empty?
          if kwargs && !keyworded?(params)
            args << kwargs
            kwargs = nil
          end
          args = splat_array(args.first) if spread && args.size == 1 && args.first.is_a?(::Array) && params.spread?
          check_arity(params, args) if strict
          bind_positional(params, scope, args, ctx)
          bind_keywords(params, scope, kwargs || {}, ctx, strict: strict)
          if params.no_block?
            raise ::ArgumentError, "no block accepted" if blk
          elsif params.block
            scope.set(params.block, blk)
          end
        end

        def keyworded?(params) = !params.keywords.empty? || (params.kwrest && params.kwrest != :nokey)

        def bind_positional(params, scope, args, ctx)
          args = args.dup
          taken = [args.size - params.required.size - params.post.size, 0].max
          params.required.each { |name| bind_one(name, args.shift, scope, ctx) }
          params.optional.each do |name, default|
            if taken.positive?
              taken -= 1
              scope.set(name, args.shift)
            else
              scope.set(name, walk(default, ctx))
            end
          end
          if params.rest?
            rest = [args.size - params.post.size, 0].max
            scope.set(params.rest, args.shift(rest))
          end
          params.post.each { |name| bind_one(name, args.shift, scope, ctx) }
        end

        def bind_one(name, value, scope, ctx)
          return spread(name, splat_array(value), ctx) if name.is_a?(Hir::MultiTarget)

          scope.set(name, value)
        end

        #: (Hir::Params params, Scope scope, Hash[Symbol, value] kwargs, Ctx ctx, strict: bool) -> value
        def bind_keywords(params, scope, kwargs, ctx, strict:)
          rest = kwargs.dup
          params.keywords.each do |name, default|
            if rest.key?(name)
              scope.set(name, rest.delete(name))
            elsif default
              scope.set(name, walk(default, ctx))
            elsif strict
              raise ::ArgumentError, "missing keyword: :#{name}"
            else
              scope.set(name, nil)
            end
          end
          return scope.set(params.kwrest, rest) if params.kwrest && params.kwrest != :nokey
          raise ::ArgumentError, "unknown keyword: #{rest.keys.first.inspect}" if strict && !rest.empty?
        end

        def check_arity(params, args)
          min = params.min_args
          max = params.max_args
          return if args.size >= min && (max.nil? || args.size <= max)

          raise ::ArgumentError, "wrong number of arguments (given #{args.size}, expected #{arity_text(min, max)})"
        end

        def arity_text(min, max)
          return "#{min}+" if max.nil?
          return min.to_s if min == max

          "#{min}..#{max}"
        end
      end
    end
  end
end
