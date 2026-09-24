# frozen_string_literal: true

require_relative "../../hir"
require_relative "../../record"

module Zr
  class Eval
    # A walk of the tree the front end built, for a program that cannot
    # write machine code while it runs.
    #
    # The front end is the compiler's own: the same prism port, the same
    # `Hir.build`, the same desugaring and name resolution. Only the back
    # half differs. Where the compiling road lowers the tree to IR and
    # writes it into the process, this evaluates the tree node by node,
    # and reaches the program through the calls any Ruby program makes --
    # `__send__`, `define_method`, `instance_variable_get` -- with
    # `Eval::World` for the tables the compiler reaches inline.
    #
    # It is slower than compiled code by a wide margin, and that is the
    # trade wasm asks for. What it will not do is answer something other
    # than ruby: a form it does not carry is refused by name, at its
    # line, as the contract asks.
    class Tree
      # A form the walk does not carry yet, named where it stands. The
      # contract lets zr refuse; it does not let zr guess.
      class Refused < ::NotImplementedError; end

      # `return`, `break`, `next`, `redo` and `retry` leave a walked body
      # the way a raise does. They descend from Exception rather than
      # StandardError so that a bare `rescue` -- in walked code, or in
      # the compiled method a walked block was passed to -- does not
      # swallow them.
      class Signal < ::Exception; end

      class Returning < Signal
        attr_reader :value, :tag

        def initialize(value, tag)
          @value = value
          @tag = tag
          super("unexpected return")
        end
      end

      class Breaking < Signal
        attr_reader :value, :tag

        def initialize(value, tag)
          @value = value
          @tag = tag
          super("break from proc-closure")
        end
      end

      class Nexting < Signal
        attr_reader :value, :tag

        def initialize(value, tag)
          @value = value
          @tag = tag
          super("unexpected next")
        end
      end

      class Redoing < Signal
        attr_reader :tag

        def initialize(tag)
          @tag = tag
          super("unexpected redo")
        end
      end

      class Retrying < Signal
        def initialize = super("retry outside of rescue clause")
      end

      # One scope's locals, by name. A scope the walk makes is its own
      # Hash; the scopes outside an eval belong to the frame that asked,
      # and `Binding` reaches them where they stand.
      class Scope
        def initialize(names)
          @values = {}
          names.each { |name| @values[name] = nil }
        end

        def holds?(name) = @values.key?(name)
        def get(name) = @values[name]
        def set(name, value) = @values[name] = value
        def names = @values.keys
      end

      # A scope of the frame that asked for the eval, as its Binding
      # names it: a read and a write land in the frame itself, so a
      # string that assigns a local the caller holds is seen there.
      class Held
        def initialize(binding, depth, names)
          @binding = binding
          @depth = depth
          @names = names
        end

        def holds?(name) = !@names.index(name).nil?
        def names = @names.compact

        def get(name)
          i = @names.index(name) or return nil
          World.binding_get(@binding, @depth, i)
        end

        def set(name, value)
          i = @names.index(name) or return value
          World.binding_set(@binding, @depth, i, value)
        end
      end

      # Where a node runs: the self it runs under, the lexical scope its
      # constants read, the chain of scopes its locals live in
      # (innermost first), the block the body was given, and -- inside a
      # method -- the name and owner a `super` goes on from, with the
      # arguments a bare `super` passes again. `tag` marks the innermost
      # block or loop, which `break`, `next` and `redo` leave; `home`
      # marks the method a `return` leaves, and is nil where the walk
      # stands in no method it can return from.
      class Ctx < Record
        FIELDS = %i[self_ cref chain block name owner args kwargs tag home].freeze
        attr_accessor :self_, :cref, :chain, :block, :name, :owner, :args, :kwargs, :tag, :home

        def initialize(self_: nil, cref: nil, chain: nil, block: nil, name: nil, owner: nil, args: nil, kwargs: nil, tag: nil,
                       home: nil)
          @self_ = self_
          @cref = cref
          @chain = chain
          @block = block
          @name = name
          @owner = owner
          @args = args
          @kwargs = kwargs
          @tag = tag
          @home = home
        end

        def to_a = [@self_, @cref, @chain, @block, @name, @owner, @args, @kwargs, @tag, @home]

        def with(**over) = Ctx.new(**to_h, **over)
      end

      def initialize(file)
        @file = file
      end

      # `hir` run under `ctx`. The value is the body's.
      def run(hir, ctx) = walk(hir.body, ctx)

      # A node's value.
      def walk(node, ctx)
        case node
        when nil then nil
        when Hir::Seq then node.stmts.map { |s| walk(s, ctx) }.last
        when Hir::Literal then node.value.is_a?(::String) ? node.value.dup : node.value
        when Hir::FrozenString then node.value
        when Hir::SelfRef then ctx.self_
        when Hir::Trace then nil
        when Hir::Send then send_node(node, ctx)
        when Hir::Local then read_local(node, ctx)
        when Hir::Assign then write_local(node, walk(node.value, ctx), ctx)
        when Hir::If then truthy(walk(node.cond, ctx)) ? walk(node.yes, ctx) : walk(node.no, ctx)
        when Hir::And then (left = walk(node.left, ctx); truthy(left) ? walk(node.right, ctx) : left)
        when Hir::Or then (left = walk(node.left, ctx); truthy(left) ? left : walk(node.right, ctx))
        when Hir::Not then !truthy(walk(node.value, ctx))
        when Hir::While then while_node(node, ctx)
        when Hir::ArrayLit then elements(node.elements, ctx)
        when Hir::HashLit then hash_lit(node.pairs, ctx)
        when Hir::KwSplatElement then kwsplat_element(node, ctx)
        when Hir::RangeLit then ::Range.new(walk(node.low, ctx), walk(node.high, ctx), node.exclusive)
        when Hir::Interp then interp(node, ctx)
        when Hir::RegexpLit then ::Regexp.new(node.source, node.options)
        when Hir::IvarRead then ctx.self_.instance_variable_get(node.name)
        when Hir::IvarWrite then ivar_write(node, ctx)
        when Hir::GvarRead then gvar_read(node)
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
        when Hir::Require then refuse(node, "require of #{node.feature.inspect}")
        when Hir::Autoload then refuse(node, "autoload of #{node.name}")
        when Hir::BackRef then refuse(node, backref_name(node))
        when Hir::RegexpOnce then refuse(node, "a /#{node.value.is_a?(Hir::RegexpLit) ? node.value.source : "..."}/o literal")
        when Hir::Using, Hir::UsingDefaults then refuse(node, "using")
        else refuse(node, node.class.name.split("::").last)
        end
      end

      private

      # `return`. A block returns from the method it was written in; an
      # eval outside a method has none, and one inside a method cannot
      # unwind the compiled frame that called it, so it is refused.
      def return_node(node, ctx)
        refuse(node, "return from an eval") unless ctx.home

        raise Returning.new(walk(node.value, ctx), ctx.home)
      end

      # `false` and `nil` are the only falsehoods, as everywhere.
      def truthy(value) = !value.nil? && value != false

      def refuse(node, what)
        raise Refused, "#{@file}:#{node.line}: #{what} is not walked yet"
      end

      def backref_name(node) = node.kind == :nth ? "$#{node.number}" : { last: "$+", pre: "$`", post: "$'" }.fetch(node.kind)

      # Locals. The chain is innermost first, and a node's `depth` counts
      # scopes out to the one that holds the name, which is how the front
      # end resolved it.
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

      # `$~` and `$_` are registers of the frame that last matched and
      # not rows of the global table, and the walk has no frame of its
      # own to keep them in: a match it makes stands in whichever of its
      # own frames ran the send. Reading them from the table would answer
      # something, and something is worse than a refusal.
      FRAME_GLOBALS = { :$~ => "$~", :$_ => "$_" }.freeze

      def gvar_read(node)
        refuse(node, FRAME_GLOBALS[node.name]) if FRAME_GLOBALS.key?(node.name)

        World.gvar_get(node.name)
      end

      def gvar_write(node, ctx)
        refuse(node, "#{FRAME_GLOBALS[node.name]} =") if FRAME_GLOBALS.key?(node.name)

        value = walk(node.value, ctx)
        World.gvar_set(node.shown || node.name, node.name, value)
        value
      end

      # A `while` or `until`; its value is nil unless a `break` names one.
      def while_node(node, ctx)
        tag = node.__id__
        inner = ctx.with(tag: tag)
        first = node.body_first
        while first || truthy(walk(node.cond, ctx))
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

      # An array literal, or a call's positional arguments: a `*splat`
      # spreads where it stands.
      def elements(nodes, ctx)
        out = []
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

      # `*value` as ruby spreads it: an Array as it stands, nil as
      # nothing, anything else through `to_a` and then as one element.
      def splat_array(value)
        return value if value.is_a?(::Array)
        return [] if value.nil?
        return value.to_a if value.respond_to?(:to_a)

        [value]
      end

      # `{k => v, **h}`: the pairs are flat, key then value, and a
      # double splat arrives as a key with a nil value.
      def hash_lit(pairs, ctx)
        out = {}
        i = 0
        while i < pairs.size
          key = pairs[i]
          if key.is_a?(Hir::HashSplat)
            spread = walk(key.value, ctx)
            out.update(spread.nil? ? {} : spread.to_hash)
            i += 2
          else
            out[walk(key, ctx)] = walk(pairs[i + 1], ctx)
            i += 2
          end
        end
        out
      end

      # `[**h]`: the pairs as one Array element, and no element at all
      # where they come out empty.
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

      # What `"#{x}"` writes: `to_s`, and `inspect` where that answers
      # something other than a String, as CRuby's rb_obj_as_string does.
      def stringify(value)
        said = value.to_s
        said.is_a?(::String) ? said : value.inspect
      end

      # Constants. The lookup is the kernel's own, so a name the string
      # spells finds what compiled code in the same scope finds.
      def const_read(node, ctx)
        return World.const_get_at(::Object, node.name) if node.scope == :top
        return World.const_get_at(walk(node.scope, ctx), node.name) if node.scope

        World.const_get(ctx.cref, node.name)
      end

      def const_write(node, value, ctx)
        World.const_set(const_base(node, ctx), node.name, value)
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

      # Where a constant a name writes lands: the scope before `::`, else
      # the innermost lexical scope, which an eval's own cref is not.
      def const_base(node, ctx)
        return ::Object if node.scope == :top
        return walk(node.scope, ctx) if node.scope

        World.cref_klass(World.cref_lexical(ctx.cref))
      end

      # The methods that read the frame that called them. The walk runs
      # in frames of its own files, not of the string, so a plain call
      # would answer for `tree.rb`. What the node's own place already
      # knows is answered from there; the rest is refused.
      FROM_THE_FRAME = %i[block_given? iterator? __method__ __callee__ local_variables].freeze
      NO_FRAME = %i[binding caller caller_locations __dir__].freeze

      # The words that set a body's own visibility, which lives in the
      # cref rather than in any frame: written bare, they change what the
      # `def`s after them get. Given names they are ordinary calls.
      VISIBILITY = { private: 1, public: 0, protected: 2 }.freeze

      # Calls.
      def send_node(node, ctx)
        refuse(node, "a call under a refinement") if node.using
        return frame_method(node, ctx) if bare?(node) && (FROM_THE_FRAME.include?(node.name) || NO_FRAME.include?(node.name))
        return body_visibility(node, ctx) if bare?(node) && (VISIBILITY.key?(node.name) || node.name == :module_function)
        refuse(node, "Module.nesting") if node.name == :nesting && node.recv.is_a?(Hir::ConstRead) && node.recv.name == :Module

        recv = node.recv ? walk(node.recv, ctx) : ctx.self_
        return nil if node.safe && recv.nil?

        args = elements(node.args, ctx)
        kwargs = node.kwargs ? hash_lit(node.kwargs.pairs, ctx) : nil
        block = block_for(node.block, ctx)
        call(recv, node.name, args, kwargs, block, private: private_call?(node), vcall: node.vcall,
                                                   breaks: node.block.is_a?(Hir::Block) && node.block)
      end

      # A private method answers a call with no receiver, and one whose
      # receiver is written `self`, as ruby lets it.
      def private_call?(node) = node.recv.nil? || node.recv.is_a?(Hir::SelfRef)

      # A call written as a bare name, with nothing after it.
      def bare?(node) = node.recv.nil? && node.args.empty? && node.kwargs.nil? && node.block.nil?

      def frame_method(node, ctx)
        case node.name
        when :block_given?, :iterator? then !ctx.block.nil?
        when :__method__, :__callee__ then ctx.name
        when :local_variables then ctx.chain.flat_map(&:names).uniq
        else refuse(node, node.name.to_s)
        end
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

      # `&value`: nil passes no block, a Proc passes itself, a Symbol
      # and anything else go through `to_proc`.
      def block_pass(value)
        return nil if value.nil?
        return value if value.is_a?(::Proc)

        value.to_proc
      end

      # One send. `vcall` marks a bare identifier, whose miss is a
      # NameError rather than a NoMethodError; `breaks` is the block
      # literal this call was given, whose `break` this call answers.
      def call(recv, name, args, kwargs, block, private:, vcall: false, breaks: nil)
        tag = breaks && breaks.__id__
        if kwargs.nil? || kwargs.empty?
          private ? recv.__send__(name, *args, &block) : recv.public_send(name, *args, &block)
        else
          private ? recv.__send__(name, *args, **kwargs, &block) : recv.public_send(name, *args, **kwargs, &block)
        end
      rescue Breaking => e
        raise unless tag && e.tag.equal?(tag)

        e.value
      rescue ::NoMethodError => e
        raise unless vcall && e.name == name && e.receiver.equal?(recv)

        raise ::NameError.new("undefined local variable or method '#{name}' for #{recv.inspect}", name, receiver: recv)
      end

      # Blocks. A block is a Proc whose body this walks; `break`, `next`
      # and `redo` in it are the signals a walked body raises, and the
      # call that was given the block answers a `break`.
      # `home` is the lexical scope every frame of this file runs under.
      # A block that finds itself under another one was handed to
      # `class_eval`, `instance_eval`, `class_exec` or `instance_exec`,
      # which run a block under a self and a definee of their own -- and
      # compiled code does that to blocks the walk made: `Forwardable`
      # evaluates a string to a proc and hands it to `module_eval`. The
      # walk follows it there.
      def make_proc(node, ctx, lambda:)
        tree = self
        home = World.cref
        # The literal is what makes a lambda a lambda: `Kernel#lambda`
        # refuses a Proc that was not written as its block.
        if lambda
          return ->(*args, **kwargs, &blk) { tree.__send__(:run_block, node, ctx, args, kwargs, blk, lambda: true, home: home, here: World.cref, self_: self) }
        end

        proc { |*args, **kwargs, &blk| tree.__send__(:run_block, node, ctx, args, kwargs, blk, lambda: false, home: home, here: World.cref, self_: self) }
      end

      def run_block(node, ctx, args, kwargs, blk, lambda:, home: nil, here: nil, self_: nil)
        ctx = ctx.with(self_: self_, cref: here, name: nil, owner: nil, home: nil) if here && !World.same?(here, home)
        tag = node.__id__
        scope = Scope.new(node.locals)
        # A `yield` in a block reaches the block of the method the block
        # was written in, not one passed to the block itself, which is
        # the `&blk` parameter's alone.
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

      # Method definition. The body is walked on every call, under the
      # lexical scope the `def` was written in.
      def define(node, ctx)
        owner = node.receiver ? World.singleton_of(walk(node.receiver, ctx)) : World.cref_klass(ctx.cref)
        tree = self
        cref = ctx.cref
        owner.define_method(node.name) do |*args, **kwargs, &blk|
          tree.__send__(:run_method, node, self, owner, cref, args, kwargs, blk)
        end
        visibility(owner, node, cref) unless node.receiver
        node.name
      end

      # What a `def` under `cref` gets beside its body: the body's
      # current visibility, and `module_function`'s copy on the
      # singleton class.
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
                      name: node.name, owner: owner, args: args, kwargs: kwargs, tag: tag, home: tag)
        bind(node.params, scope, args, kwargs, blk, ctx, strict: true, spread: false)
        begin
          walk(node.body, ctx)
        rescue Returning => e
          raise unless e.tag.equal?(tag)

          e.value
        end
      end

      # Class and module bodies.
      def module_def(node, ctx)
        base = node.scope == :top ? ::Object : node.scope ? walk(node.scope, ctx) : World.cref_klass(World.cref_lexical(ctx.cref))
        mod = World.const_defined_at?(base, node.name) ? World.const_get_at(base, node.name) : nil
        mod ||= World.const_set(base, node.name, new_module(node, ctx))
        run_body(node, mod, ctx)
      end

      def new_module(node, ctx)
        return ::Module.new unless node.is_a?(Hir::ClassDef)

        node.superclass ? ::Class.new(walk(node.superclass, ctx)) : ::Class.new
      end

      def singleton_def(node, ctx) = run_body(node, World.singleton_of(walk(node.target, ctx)), ctx)

      # A class, module or singleton class body: its own scope, its own
      # self, and a lexical scope one inside the one it was written in.
      def run_body(node, mod, ctx)
        inner = Ctx.new(self_: mod, cref: World.cref_push(mod, ctx.cref), chain: [Scope.new(node.locals)],
                        block: nil, name: nil, owner: nil, args: nil, kwargs: nil, tag: node.__id__, home: nil)
        walk(node.body, inner)
      end

      # `begin ... rescue ... else ... ensure ... end`.
      def begin_node(node, ctx)
        # `retry` runs the protected body again, not the clause that
        # asked for it, so it is caught outside both.
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
        subject = node.subject ? [walk(node.subject, ctx)] : nil
        node.clauses.each do |values, body|
          return walk(body, ctx) if values.any? { |v| matches?(v, subject, ctx) }
        end
        walk(node.else_body, ctx)
      end

      # One `when` value against the subject, or its own truth where the
      # `case` named none. A `*splat` among them tests each element.
      def matches?(value, subject, ctx)
        if value.is_a?(Hir::Splat)
          return splat_array(walk(value.value, ctx)).any? { |v| subject ? truthy(v === subject.first) : truthy(v) }
        end
        v = walk(value, ctx)
        subject ? truthy(v === subject.first) : truthy(v)
      end

      # `a, (b, *c), *d, e = value`.
      def multi_assign(node, ctx)
        value = walk(node.value, ctx)
        spread(node.target, splat_array(value), ctx)
        value
      end

      def spread(target, values, ctx)
        values = values.dup
        target.lefts.each { |t| write_target(t, values.shift, ctx) }
        rest = target.rest
        if rest
          take = values.size - target.rights.size
          taken = take.positive? ? values.shift(take) : []
          write_target(rest, taken, ctx) unless rest == :implicit
        end
        target.rights.each { |t| write_target(t, values.shift, ctx) }
        values
      end

      # One target of a multiple assignment, a rescue's `=> e` or a
      # destructuring parameter: a local, an ivar, a `h[k]` or an
      # attribute, or a nested target.
      def write_target(target, value, ctx)
        case target
        when Hir::Assign then write_local(target, value, ctx)
        when Hir::IvarWrite then ctx.self_.instance_variable_set(target.name, value)
        when Hir::GvarWrite then World.gvar_set(target.shown || target.name, target.name, value)
        when Hir::CvarWrite then World.cvar_set(ctx.cref, target.name, value)
        when Hir::ConstWrite then World.const_set(const_base(target, ctx), target.name, value)
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
        kwargs = node.kwargs ? hash_lit(node.kwargs.pairs, ctx) : nil
        kwargs.nil? || kwargs.empty? ? block.call(*args) : block.call(*args, **kwargs)
      end

      # `super(args)` and the bare `super`, which passes the method's own
      # arguments again. The entry is the next one after the method's
      # owner along the receiver's own ancestors, which is what the
      # runtime's own lookup answers.
      def super_node(node, ctx)
        args = elements(node.args, ctx)
        kwargs = node.kwargs ? hash_lit(node.kwargs.pairs, ctx) : nil
        call_super(node, ctx, args, kwargs, block_for(node.block, ctx) || ctx.block)
      end

      def zsuper_node(node, ctx)
        call_super(node, ctx, ctx.args || [], ctx.kwargs, block_for(node.block, ctx) || ctx.block)
      end

      def call_super(node, ctx, args, kwargs, block)
        refuse(node, "super outside a method") unless ctx.name && ctx.owner
        method = super_method(node, ctx)
        if kwargs.nil? || kwargs.empty?
          method.bind_call(ctx.self_, *args, &block)
        else
          method.bind_call(ctx.self_, *args, **kwargs, &block)
        end
      end

      def super_method(_node, ctx)
        chain = ctx.self_.class.ancestors
        chain = ctx.self_.singleton_class.ancestors if ctx.self_.singleton_class.ancestors.include?(ctx.owner)
        at = chain.index(ctx.owner)
        found = at && chain[(at + 1)..].find { |m| m.method_defined?(ctx.name, false) || m.private_method_defined?(ctx.name, false) }
        found or raise ::NoMethodError.new("super: no superclass method '#{ctx.name}'", ctx.name, receiver: ctx.self_)

        found.instance_method(ctx.name)
      end

      # `defined?(...)`: the word ruby answers, or nil.
      def defined_node(node, ctx)
        case node.kind
        when :self then "self"
        when :nil then "expression"
        when :true then "expression"
        when :false then "expression"
        when :assignment then "assignment"
        when :yield then ctx.block ? "yield" : nil
        when :local then ctx.chain.any? { |s| s.holds?(node.target) } ? "local-variable" : nil
        when :ivar then ctx.self_.instance_variable_defined?(node.target) ? "instance-variable" : nil
        when :gvar then truthy(World.gvar_defined?(node.target)) ? "global-variable" : nil
        when :cvar then truthy(World.cvar_defined?(ctx.cref, node.target)) ? "class variable" : nil
        when :const then defined_const(node, ctx)
        when :method then defined_method(node, ctx)
        when :expression then defined_expression(node, ctx)
        else refuse(node, "defined?(#{node.kind})")
        end
      end

      def defined_const(node, ctx)
        truthy(const_defined?(node.target, ctx)) ? "constant" : nil
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

      # Every other form is an expression, and `defined?` answers so
      # without running it.
      def defined_expression(_node, _ctx) = "expression"

      # `recv[args] op= value` and `recv.name op= value`: the receiver
      # and the arguments are evaluated once.
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

        current = call(recv, node.name, [], nil, nil, private: private_call?(node))
        return current if short_circuit?(node.op, current)

        value = combined(node.op, current, node.value, ctx)
        call(recv, :"#{node.name}=", [value], nil, nil, private: private_call?(node))
        value
      end

      def short_circuit?(op, current) = (op == :or && truthy(current)) || (op == :and && !truthy(current))

      def combined(op, current, value_node, ctx)
        return walk(value_node, ctx) if op == :or || op == :and

        current.public_send(op, walk(value_node, ctx))
      end

      def alias_node(_node, ctx, new_name, old_name)
        World.alias_method(World.cref_klass(ctx.cref), new_name.to_sym, old_name.to_sym)
        nil
      end

      def undef_node(_node, ctx, names)
        mod = World.cref_klass(ctx.cref)
        names.each { |name| mod.send(:undef_method, name.to_sym) }
        nil
      end

      # `END { }`: the body runs the first time the site is reached.
      def once(node, ctx)
        @once ||= {}.compare_by_identity
        return @once[node] if @once.key?(node)

        @once[node] = walk(node.body, ctx)
      end

      # Parameters. `args` are the positional arguments, `kwargs` the
      # keywords or nil, and `strict` asks for the arity check a method
      # and a lambda make and a block does not.
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
        scope.set(params.block, blk) if params.block
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
