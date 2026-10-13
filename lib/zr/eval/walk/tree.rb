# frozen_string_literal: true

require_relative "../../hir"
require_relative "../../refused"

module Zr
  class Eval
    # The tree-walking back end of eval (`lib/zr/eval/walk.rb`).
    module Walk
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
        # @rbs @once: Hash[Hir::Once, untyped]?
        # @rbs @regexps: Hash[Hir::RegexpLit | Hir::RegexpOnce, Regexp]?
        # @rbs @svars: untyped

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

        class Returning < Signal
          attr_reader :value, :tag #: untyped

          #: (untyped value, untyped tag) -> void
          def initialize(value, tag)
            @value = value
            @tag = tag
            super("unexpected return")
          end
        end

        class Breaking < Signal
          attr_reader :value, :tag #: untyped

          #: (untyped value, untyped tag) -> void
          def initialize(value, tag)
            @value = value
            @tag = tag
            super("break from proc-closure")
          end
        end

        class Nexting < Signal
          attr_reader :value, :tag #: untyped

          #: (untyped value, untyped tag) -> void
          def initialize(value, tag)
            @value = value
            @tag = tag
            super("unexpected next")
          end
        end

        class Redoing < Signal
          attr_reader :tag #: untyped

          #: (untyped tag) -> void
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
          # @rbs @values: Hash[Symbol, untyped]

          #: (Array[Symbol] names) -> void
          def initialize(names)
            @values = {}
            names.each { |name| @values[name] = nil }
          end

          #: (Symbol name) -> bool
          def holds?(name) = @values.key?(name)
          #: (Symbol name) -> untyped
          def get(name) = @values[name]
          #: (Symbol name, untyped value) -> untyped
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

          #: (Symbol name) -> untyped
          def get(name)
            i = @names.index(name) or return nil
            World.binding_get(@binding, @depth, i)
          end

          #: (Symbol name, untyped value) -> untyped
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
        # is the cell of the frame that called eval.
        # @rbs skip -- typed in sig/zr/eval/walk/tree.rbs
        Ctx = Data.define(:self_, :cref, :chain, :block, :name, :owner, :args, :kwargs, :tag, :home, :svars)

        # `frame` is the Binding of the frame that called eval: the scope
        # that a `return`, `$~` and `binding` of the string belong to.
        #: (String file, Binding frame) -> void
        def initialize(file, frame)
          @file = file
          @frame = frame
        end

        # Runs `hir` in `ctx` and returns the value of its body.
        #: (Hir::Program hir, Ctx ctx) -> untyped
        def run(hir, ctx) = walk(hir.body, ctx)

        def walk(node, ctx)
          case node
          when nil then nil
          when Hir::Seq then node.stmts.map { |s| walk(s, ctx) }.last
          when Hir::Literal then literal(node)
          when Hir::PathLiteral then World.path(literal(node.literal))
          when Hir::FrozenString then node.value
          when Hir::SelfRef then ctx.self_
          when Hir::Trace then nil
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
          when Hir::Alias then alias_node(node, ctx, node.new_name, node.old_name)
          when Hir::AliasValue then alias_node(node, ctx, walk(node.new_name, ctx), walk(node.old_name, ctx))
          when Hir::Undef then undef_node(node, ctx, node.names)
          when Hir::UndefValue then undef_node(node, ctx, node.names.map { |n| walk(n, ctx) })
          when Hir::Core then ::Object.const_get(node.name)
          when Hir::Once then once(node, ctx)
          when Hir::Stop then raise ::NotImplementedError, "#{@file}:#{node.line}: #{node.what}"
          when Hir::ExtInit then raise ::NotImplementedError, "#{node.path}: a C extension runs only in a binary"
          when Hir::Require then refuse(node, "require of #{node.feature.inspect}")
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

        # A Regexp literal is one frozen object for its site, as ruby
        # makes it once when it compiles the string.
        #: (Hir::RegexpLit node) -> Regexp
        def regexp(node) = regexps[node] ||= ::Regexp.new(node.source, node.options).freeze

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

        def backref_name(node) = node.kind == :nth ? "$#{node.number}" : { last: "$+", pre: "$`", post: "$'" }.fetch(node.kind)

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
        def svars(ctx) = ctx.svars || (@svars ||= World.binding_svars(@frame))

        def gvar_read(node, ctx)
          slot = FRAME_GLOBALS[node.name]
          return svars(ctx)[slot] if slot

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
        #: (Array[Hir::node] nodes, Ctx ctx) -> Array[untyped]
        def elements(nodes, ctx)
          out = [] #: Array[untyped]
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
        #: (Array[Hir::node?] pairs, Ctx ctx) -> Hash[untyped, untyped]
        def hash_lit(pairs, ctx)
          out = {} #: Hash[untyped, untyped]
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
          return World.const_get_at(walk(node.scope, ctx), node.name) if node.scope

          World.const_get(ctx.cref, node.name)
        end

        def const_write(node, value, ctx)
          # Steep finds Module#const_set on World before World#const_set.
          World.const_set(const_base(node, ctx), node.name, value) # steep:ignore UnexpectedPositionalArgument
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
        # context knows (FROM_THE_FRAME) and refuses the rest (NO_FRAME).
        FROM_THE_FRAME = %i[block_given? iterator? __method__ __callee__ local_variables binding __dir__].freeze
        NO_FRAME = %i[caller caller_locations].freeze

        # The words that set the default visibility of a body. It is in
        # the cref, not in a frame. Without arguments, they change the
        # visibility of the next `def`s. With names, they are usual calls.
        VISIBILITY = { private: 1, public: 0, protected: 2 }.freeze

        def send_node(node, ctx)
          refuse(node, "a call under a refinement") if node.using
          return frame_method(node, ctx) if bare?(node) && (FROM_THE_FRAME.include?(node.name) || NO_FRAME.include?(node.name))
          return body_visibility(node, ctx) if bare?(node) && (VISIBILITY.key?(node.name) || node.name == :module_function)
          recv = node.recv ? walk(node.recv, ctx) : ctx.self_
          return World.nesting(ctx.cref) if node.name == :nesting && recv.equal?(::Module) && node.args.empty? && node.block.nil?
          return nil if node.safe && recv.nil?
          return recv if node.interp && (String === recv || Symbol === recv)

          args = elements(node.args, ctx)
          kwargs = node.kwargs ? hash_lit(node.kwargs.pairs, ctx) : nil
          block = block_for(node.block, ctx)
          call(recv, node.name, args, kwargs, block, private: private_call?(node), vcall: node.vcall,
                                                     breaks: node.block.is_a?(Hir::Block) && node.block,
                                                     svars: (svars(ctx) if svar_send?(recv, node.name)))
        end

        # The core methods that set or read their caller's `$~` or `$_`. In
        # ruby they are C functions, which see the frame of their caller.
        # Most are methods of String, Symbol and Regexp, so an Array's `[]`
        # does not pay for them; a line read and `print` go to any receiver.
        TEXT_SVAR_SENDS = %i[=~ !~ === ~ match scan sub sub! gsub gsub! index rindex byteindex byterindex [] slice slice!
                             start_with? partition rpartition last_match].to_h { |name| [name, true] }.freeze
        LINE_SVAR_SENDS = %i[gets readline print].to_h { |name| [name, true] }.freeze

        def svar_send?(recv, name)
          return true if LINE_SVAR_SENDS.key?(name)

          TEXT_SVAR_SENDS.key?(name) && (::String === recv || ::Symbol === recv || ::Regexp === recv || recv.equal?(::Regexp))
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
        # that the string's own scopes hold. It copies their values: a later
        # write in the string does not reach it.
        def scope_binding(ctx)
          scope = @frame.dup
          ctx.chain.each do |held|
            next unless held.is_a?(Scope)

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
        # @rbs recv: untyped
        # @rbs name: Symbol
        # @rbs args: Array[untyped]
        # @rbs kwargs: Hash[Symbol, untyped]?
        # @rbs block: Proc?
        # @rbs private: bool
        # @rbs vcall: bool
        # @rbs breaks: Hir::Block | false | nil
        # @rbs svars: untyped
        # @rbs return: untyped
        def call(recv, name, args, kwargs, block, private:, vcall: false, breaks: nil, svars: nil)
          tag = breaks && breaks.__id__
          if svars
            svar_send(recv, name, args, kwargs, block, private, svars)
          elsif kwargs.nil? || kwargs.empty?
            private ? recv.__send__(name, *args, &block) : recv.public_send(name, *args, &block)
          else
            private ? recv.__send__(name, *args, **kwargs, &block) : recv.public_send(name, *args, **kwargs, &block)
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
        #: (untyped recv, Symbol name, Array[untyped] args, Hash[Symbol, untyped]? kwargs, untyped block, bool private, untyped cell) -> untyped
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
          if lambda
            return ->(*args, **kwargs, &blk) { tree.__send__(:run_block, node, ctx, args, kwargs, blk, lambda: true, home: home, here: World.cref, self_: self) } # steep:ignore FallbackAny
          end

          proc { |*args, **kwargs, &blk| tree.__send__(:run_block, node, ctx, args, kwargs, blk, lambda: false, home: home, here: World.cref, self_: self) } # steep:ignore FallbackAny
        end

        # `home` and `here` are crefs (`World.cref`).
        # @rbs node: Hir::Block
        # @rbs ctx: Ctx
        # @rbs args: Array[untyped]
        # @rbs kwargs: Hash[Symbol, untyped]?
        # @rbs blk: Proc?
        # @rbs lambda: bool
        # @rbs home: untyped
        # @rbs here: untyped
        # @rbs self_: untyped
        # @rbs return: untyped
        def run_block(node, ctx, args, kwargs, blk, lambda:, home: nil, here: nil, self_: nil)
          ctx = ctx.with(self_: self_, cref: here, name: nil, owner: nil, home: nil) if here && !World.same?(here, home)
          tag = node.__id__
          scope = Scope.new(node.locals)
          # A `yield` in a block calls the block of the method that
          # contains the block. A block passed to the block itself is only
          # in its `&blk` parameter.
          inner = ctx.with(chain: [scope, *ctx.chain], tag: tag)
          bind(node.params, scope, args, kwargs, blk, inner, strict: lambda, spread: !lambda)
          begin
            walk(node.body, inner)
          rescue Nexting => e
            raise unless e.tag.equal?(tag)

            e.value
          rescue Redoing => e
            raise unless e.tag.equal?(tag)

            retry
          end
        end

        # Method definition. Each call walks the body, in the lexical scope
        # of the `def`.
        def define(node, ctx)
          owner = node.receiver ? World.singleton_of(walk(node.receiver, ctx)) : World.cref_definee(ctx.cref)
          tree = self
          cref = ctx.cref
          # The program gives the arguments, so Steep cannot type them.
          owner.define_method(node.name) do |*args, **kwargs, &blk|
            tree.__send__(:run_method, node, self, owner, cref, args, kwargs, blk) # steep:ignore FallbackAny
          end
          visibility(owner, node, cref) unless node.receiver
          node.name
        end

        # Applies to a `def` in `cref` the current default visibility of the
        # body, and the singleton copy that `module_function` makes.
        def visibility(owner, node, cref)
          owner.singleton_class.send(:define_method, node.name, owner.instance_method(node.name)) if World.module_function?(cref)
          case World.definition_vis(node.name, cref)
          when 1 then owner.send(:private, node.name)
          when 2 then owner.send(:protected, node.name)
          end
        end

        def run_method(node, self_, owner, cref, args, kwargs, blk)
          tag = node.__id__
          scope = Scope.new(node.locals)
          ctx = Ctx.new(self_: self_, cref: cref, chain: [scope], block: blk,
                        name: node.name, owner: owner, args: args, kwargs: kwargs, tag: tag, home: tag, svars: [nil, nil])
          bind(node.params, scope, args, kwargs, blk, ctx, strict: true, spread: false)
          begin
            walk(node.body, ctx)
          rescue Returning => e
            raise unless e.tag.equal?(tag)

            e.value
          end
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
                  World.class_define(base, node.name, sup, !node.superclass.nil?, scoped)
                else
                  World.module_define(base, node.name, scoped)
                end
          run_body(node, mod, ctx)
        end

        def singleton_def(node, ctx) = run_body(node, World.singleton_of(walk(node.target, ctx)), ctx)

        # A class, module or singleton class body: its own scope, its own
        # self, and a lexical scope one level inside the enclosing scope.
        def run_body(node, mod, ctx)
          inner = Ctx.new(self_: mod, cref: World.cref_push(mod, ctx.cref), chain: [Scope.new(node.locals)],
                          block: nil, name: nil, owner: nil, args: nil, kwargs: nil, tag: node.__id__, home: nil, svars: [nil, nil])
          walk(node.body, inner)
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
              value = walk(clause.body, ctx)
            end
            value
          rescue Retrying
            retry
          end
        ensure
          walk(node.ensure_body, ctx) if node.ensure_body
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
        def matches?(value, subject, ctx)
          if value.is_a?(Hir::Splat)
            return splat_array(walk(value.value, ctx)).any? { |v| subject ? truthy?(v === subject.first) : truthy?(v) }
          end
          v = walk(value, ctx)
          return truthy?(v) unless subject
          return truthy?(svar_send(v, :===, [subject.first], nil, nil, false, svars(ctx))) if v.is_a?(::Regexp)

          truthy?(v === subject.first)
        end

        # `a, (b, *c), *d, e = value`.
        def multi_assign(node, ctx)
          value = walk(node.value, ctx)
          spread(node.target, splat_array(value), ctx)
          value
        end

        #: (Hir::MultiTarget target, Array[untyped] values, Ctx ctx) -> Array[untyped]
        def spread(target, values, ctx)
          values = values.dup
          target.lefts.each { |t| write_target(t, values.shift, ctx) }
          rest = target.rest
          if rest
            take = values.size - target.rights.size
            taken = [] #: Array[untyped]
            taken = values.shift(take) if take.positive?
            write_target(rest, taken, ctx) unless rest == :implicit
          end
          target.rights.each { |t| write_target(t, values.shift, ctx) }
          values
        end

        # One target of a multiple assignment, of a rescue `=> e`, or of a
        # destructuring parameter: a local, a variable, a constant, a
        # `h[k]` or an attribute, or a nested target.
        def write_target(target, value, ctx)
          case target
          when Hir::Assign then write_local(target, value, ctx)
          when Hir::IvarWrite then ctx.self_.instance_variable_set(target.name, value)
          when Hir::GvarWrite then World.gvar_set(target.shown || target.name, target.name, value)
          when Hir::CvarWrite then World.cvar_set(ctx.cref, target.name, value)
          # Steep finds Module#const_set on World before World#const_set.
          when Hir::ConstWrite then World.const_set(const_base(target, ctx), target.name, value) # steep:ignore UnexpectedPositionalArgument
          when Hir::MultiTarget then spread(target, splat_array(value), ctx)
          when Hir::Send then write_send(target, value, ctx)
          else refuse(target, "#{target.class.name.split("::").last} as an assignment target")
          end
        end

        def write_send(target, value, ctx)
          recv = target.recv ? walk(target.recv, ctx) : ctx.self_
          args = elements(target.args, ctx)
          call(recv, target.name, args + [value], nil, nil, private: private_call?(target))
          value
        end

        def yield_node(node, ctx)
          block = ctx.block or raise ::LocalJumpError, "no block given (yield)"
          args = elements(node.args, ctx)
          kwargs = node.kwargs ? hash_lit(node.kwargs.pairs, ctx) : nil #: Hash[Symbol, untyped]?
          kwargs.nil? || kwargs.empty? ? block.call(*args) : block.call(*args, **kwargs)
        end

        # `super(args)` and the bare `super`, which passes the arguments of
        # the method again. The target is the next module after the owner
        # of the method in the ancestors of the receiver, as in the lookup
        # of the runtime.
        def super_node(node, ctx)
          args = elements(node.args, ctx)
          kwargs = node.kwargs ? hash_lit(node.kwargs.pairs, ctx) : nil
          call_super(node, ctx, args, kwargs, block_for(node.block, ctx) || ctx.block)
        end

        def zsuper_node(node, ctx)
          call_super(node, ctx, ctx.args || [], ctx.kwargs, block_for(node.block, ctx) || ctx.block)
        end

        # In a method that the string defines, `super` starts after that
        # method's owner. Elsewhere it belongs to the method of the frame
        # that called eval.
        #: (untyped node, Ctx ctx, Array[untyped] args, Hash[Symbol, untyped]? kwargs, (^(*untyped) -> untyped)? block) -> untyped
        def call_super(_node, ctx, args, kwargs, block)
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
        #: (untyped self_, Symbol name, Module owner) -> UnboundMethod?
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
          when :expression then defined_expression(node, ctx)
          when :global then "global-variable"
          when :backref then walk(node.target, ctx).nil? ? nil : "global-variable"
          when :super then defined_super(ctx)
          else refuse(node, "defined?(#{node.kind})")
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

        # All other forms are expressions. `defined?` returns "expression"
        # and does not run them.
        def defined_expression(_node, _ctx) = "expression"

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

          none = [] #: Array[untyped]
          current = call(recv, node.name, none, nil, nil, private: private_call?(node))
          return current if short_circuit?(node.op, current)

          value = combined(node.op, current, node.value, ctx)
          call(recv, :"#{node.name}=", [value], nil, nil, private: private_call?(node))
          value
        end

        def short_circuit?(op, current) = (op == :or && truthy?(current)) || (op == :and && !truthy?(current))

        def combined(op, current, value_node, ctx)
          return walk(value_node, ctx) if op == :or || op == :and

          current.public_send(op, walk(value_node, ctx))
        end

        def alias_node(_node, ctx, new_name, old_name)
          # Steep finds Module#alias_method on World before World#alias_method.
          World.alias_method(World.cref_definee(ctx.cref), new_name.to_sym, old_name.to_sym) # steep:ignore UnexpectedPositionalArgument
          nil
        end

        def undef_node(_node, ctx, names)
          mod = World.cref_definee(ctx.cref)
          names.each { |name| mod.send(:undef_method, name.to_sym) }
          nil
        end

        # `END { }`: the body runs only the first time that execution gets
        # to the site.
        #: (Hir::Once node, Ctx ctx) -> untyped
        def once(node, ctx)
          once = @once ||= begin
            seen = {} #: Hash[Hir::Once, untyped]
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
        # @rbs args: Array[untyped]
        # @rbs kwargs: Hash[Symbol, untyped]?
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
          check_arity(params, args, kwargs, ctx) if strict
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
          if params.rest && params.rest != :implicit
            rest = [args.size - params.post.size, 0].max
            scope.set(params.rest, args.shift(rest))
          end
          params.post.each { |name| bind_one(name, args.shift, scope, ctx) }
        end

        def bind_one(name, value, scope, ctx)
          return spread(name, splat_array(value), ctx) if name.is_a?(Hir::MultiTarget)

          scope.set(name, value)
        end

        #: (Hir::Params params, Scope scope, Hash[Symbol, untyped] kwargs, Ctx ctx, strict: bool) -> untyped
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

        def check_arity(params, args, _kwargs, _ctx)
          min = params.required.size + params.post.size
          max = params.rest ? nil : min + params.optional.size
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
