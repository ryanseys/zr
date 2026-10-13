# frozen_string_literal: true

module Zr
  module Machine
    class Host
      class Walk
        # The code of sends, as `Lower::Function::Sends` emits them: a
        # send through its site's cell, an operator's inline path, a block
        # literal as an image in the slot area, `yield`, `super`, and the
        # core's `Primitive` calls.
        module Sends
          # @type instance: Walk
          # The ivars of Walk that this module reads (walk.rb):
          # @rbs @host: Host
          # @rbs @kern: untyped
          # @rbs @qnil: Integer
          # @rbs @qtrue: Integer
          # @rbs @qfalse: Integer
          # @rbs @qundef: Integer
          # @rbs @sites: Hash[untyped, Integer]
          # @rbs @fns: Hash[untyped, untyped]
          # @rbs @funcall_of: Hash[Hir::Send, Hir::Send]
          # @rbs @funcalls: Hash[Hir::Send, bool]
          # @rbs @integer: Integer
          # @rbs @basic_klass: Integer
          # @rbs @site_stamp: Integer
          # @rbs @cc_klass: Integer
          # @rbs @cc_stamp: Integer
          # @rbs @cc_entry: Integer
          # @rbs @cc_found: Integer
          # @rbs @cc_fn: Integer
          # @rbs @proc_fn: Integer
          # @rbs @proc_env: Integer
          # @rbs @proc_self: Integer
          # @rbs @proc_cref: Integer
          # @rbs @proc_blk: Integer
          # @rbs @proc_ret_home: Integer
          # @rbs @proc_ret_serial: Integer
          # @rbs @proc_lambda: Integer
          # @rbs @task_refine: ^(Integer, untyped) -> untyped

          SEND_CORE = 8
          SEND_USING = 16

          # The names that the core's sends dispatch normally
          # (Lower::Function::Sends::PROTOCOL); any other core send finds the
          # core's own method (SEND_CORE).
          PROTOCOL = %i[
            initialize initialize_copy initialize_dup initialize_clone
            to_s inspect to_str to_sym to_proc to_ary to_a to_hash to_h to_int to_i to_f to_r to_c to_path to_io to_regexp
            == != eql? hash <=> === =~ ! coerce
            call write warn default
            respond_to? respond_to_missing? method_missing
            method_added singleton_method_added method_removed singleton_method_removed method_undefined
            singleton_method_undefined inherited included extended prepended const_added const_missing
            marshal_dump marshal_load _dump _load pp
            exception message backtrace full_message detailed_message
          ].to_set.freeze

          # The kernel entry of each send with a core fast path, and the
          # classes it takes (Lower::Function::Sends::OPT_ENTRIES). The
          # entry calls the core's method with no frame of its own, as
          # CRuby's specialized instructions do.
          OPT_ENTRIES = {
            :[] => [:zr_opt_aref, %i[G_ARRAY G_HASH]], :[]= => [:zr_opt_aset, %i[G_ARRAY G_HASH]], :<< => [:zr_opt_ltlt, %i[G_ARRAY G_STRING]],
            getbyte: [:zr_opt_getbyte, %i[G_STRING]], setbyte: [:zr_opt_setbyte, %i[G_STRING]],
            push: [:zr_opt_push, %i[G_ARRAY]], pop: [:zr_opt_pop, %i[G_ARRAY]], shift: [:zr_opt_shift, %i[G_ARRAY]],
            empty?: [:zr_opt_empty_p, %i[G_ARRAY]]
          }.freeze

          # The Integer operators with an inline path on two fixnums while
          # the operator's gate is clear (Lower::Function::Sends::OPS), each
          # with its gate and its result: nil when the result is no fixnum (a
          # bignum, a division by zero), and the send runs instead.
          FIXNUM = (-(1 << 62))...(1 << 62)
          FIXNUM_OPS = {
            :+ => [:GATE_PLUS, ->(a, b) { a + b }], :- => [:GATE_MINUS, ->(a, b) { a - b }], :* => [:GATE_MUL, ->(a, b) { a * b }],
            :/ => [:GATE_DIV, ->(a, b) { b.zero? ? nil : a / b }], :% => [:GATE_MOD, ->(a, b) { b.zero? ? nil : a % b }],
            :< => [:GATE_LT, ->(a, b) { a < b }], :<= => [:GATE_LE, ->(a, b) { a <= b }], :> => [:GATE_GT, ->(a, b) { a > b }],
            :>= => [:GATE_GE, ->(a, b) { a >= b }], :== => [:GATE_EQ, ->(a, b) { a == b }], :!= => [:GATE_NE, ->(a, b) { a != b }],
            :& => [:GATE_AND, ->(a, b) { a & b }], :| => [:GATE_OR, ->(a, b) { a | b }], :^ => [:GATE_XOR, ->(a, b) { a ^ b }],
            :>> => [:GATE_SHR, ->(a, b) { b.between?(0, 62) ? a >> b : nil }]
          }.freeze

          # The operators with a flonum path, and Float's gate of each
          # (Lower::Function::Sends::FLOAT_OPS).
          FLOAT_OPS = {
            :+ => :GATE_FLO_PLUS, :- => :GATE_FLO_MINUS, :* => :GATE_FLO_MUL, :/ => :GATE_FLO_DIV,
            :< => :GATE_FLO_LT, :<= => :GATE_FLO_LE, :> => :GATE_FLO_GT, :>= => :GATE_FLO_GE, :== => :GATE_FLO_EQ
          }.freeze
          FLOAT_COMPARES = %i[< <= > >= ==].freeze

          private

          # `recv` is the code of the receiver when the caller has its value
          # already (`Control#defined_receiver`).
          def send_node(node, s, recv = nil)
            return primitive(node, s) if s.internal? && primitive?(node)
            return send_node(funcall(node), s) if kernel_send?(node, s)

            recv ||= receiver(node.recv, s)
            args, splat = arguments(node.args, s)
            op, between = fast_paths(node, s, splat)
            kwargs = node.kwargs && hash(node.kwargs, s)
            block = block_arg(node.block, s, node)
            site = node.block.is_a?(Hir::Block) ? @sites[node.block] : nil
            dispatch = dispatcher(node, s, send_mode(node, s))
            word = line_word(node, s)
            using = node.using
            # Proc#call and Proc#yield pass a `**h` on to the block as a
            # yield does, also an empty one (`Lower::Function::Sends`).
            kw_argc = %i[call yield].include?(node.name) ? :zr_kw_argc_yield : :zr_kw_argc
            ruby2_out = %i[call yield].include?(node.name) ? :zr_kw_ruby2_out_yield : :zr_kw_ruby2_out
            safe = node.safe
            covers = node.covers
            interp = node.interp
            write = node.write
            unless splat || kwargs || node.block || safe || interp || write
              # Most sends: positional arguments only.
              return lambda do |f|
                r = recv.call(f)
                values = args.map { |a| a.call(f) }
                if op && (v = op.call(r, values.first))
                  next v
                elsif between
                  next slots(f) { check(@kern.zr_native_between(r, argv(f, values))) }
                end

                stack = f.stack
                top = stack.top
                begin
                  av = argv(f, values)
                  line!(f, word)
                  activate(using, f) if using
                  result = dispatch.call(r, values.size, av, @qnil)
                  @task_refine.call(task, @qnil) if using
                  check(result)
                ensure
                  stack.top = top
                end
              end
            end

            lambda do |f|
              r = recv.call(f)
              if safe
                # Coverage counts the call's branch or the nil branch
                # (`Sends#safe_call`).
                @kern.zr_coverage_branch((r == @qnil ? covers.last : covers.first).id) if covers
                next @qnil if r == @qnil
              end
              next r if interp && @kern.zr_interp_plain_p(r)

              if splat
                list = splat.call(f)
              else
                values = args.map { |a| a.call(f) }
                if op && (v = op.call(r, values.first))
                  next v
                elsif between
                  next slots(f) { check(@kern.zr_native_between(r, argv(f, values))) }
                end
              end
              kw = kwargs&.call(f)
              stack = f.stack
              top = stack.top
              written = nil #: Integer?
              result = begin
                blk = block.call(f)
                values = elements(list) if splat
                written = values.last
                values += [kw] if kw
                av = argv(f, values)
                argc = values.size
                argc = @kern.public_send(kw_argc, argc, av) if kw
                argc = @kern.public_send(ruby2_out, argc, av) if splat && !kw
                line!(f, word)
                activate(using, f) if using
                answer = dispatch.call(r, argc, av, blk)
                @task_refine.call(task, @qnil) if using
                sent(f, site, answer)
              ensure
                stack.top = top
              end
              write ? written : result
            end
          end

          def primitive?(node) = node.recv.is_a?(Hir::ConstRead) && node.recv.name == :Primitive && node.recv.scope.nil?

          # The send's mode for the kernel: 1 for a vcall, 2 for an explicit
          # receiver, with SEND_CORE and SEND_USING.
          def send_mode(node, s)
            mode = if node.vcall then 1
                   elsif node.recv && !node.recv.is_a?(Hir::SelfRef) && !@funcalls.key?(node) then 2
                   else 0
                   end
            # A literal `send` in the core is rb_funcall: the program's own
            # method answers it, as any send from CRuby's C does.
            mode |= SEND_CORE if core_send?(node.name, s) && !@funcalls.key?(node)
            mode |= SEND_USING if node.using
            mode
          end

          # A send's paths with no send: an operator with one argument
          # (`operator`), and the core's range check of its own integers.
          def fast_paths(node, s, splat)
            return [nil, false] if splat || node.block || node.kwargs || node.vcall || node.using == :owner || s.unit.traced

            case node.args.size
            when 1 then [operator(node.name, s, [node.recv, node.args.first]), false]
            when 2 then [nil, node.name == :between? && node.recv && !node.recv.is_a?(Hir::SelfRef) && native_operators?(s)]
            else [nil, false]
            end
          end

          # Whether a `new` runs with no frame of its own (the kernel's
          # opt_new), as the lowering's `new_send` gives it: one with no
          # block, any of the core's, as C makes it, and one with a block
          # literal in a program that fires no events (a traced one sends
          # Class#new, so a :c_call sees it).
          def frameless_new?(node, s)
            return true if node.block.nil? || s.internal?

            node.block.is_a?(Hir::Block) && !s.unit.traced
          end

          # The code that calls the method a send finds, with the receiver,
          # the argument count and vector, and the block.
          def dispatcher(node, s, mode)
            size = k::CallCache.size
            name = id(node.name)
            if node.name == :new && frameless_new?(node, s)
              at = cell(node, :new, size * 8)
              return ->(r, argc, av, blk) { @kern.zr_new_cached(at, r, argc, av, blk, mode) }
            end

            at = cell(node, :cc, size * 4)
            return ->(r, argc, av, blk) { @kern.zr_send_cached(at, r, name, argc, av, blk, mode) } if node.using == :owner

            send = cached_send(at, name, mode)
            return send unless node.opt && !s.unit.traced

            # The kernel entry for a site with a fast path (`Sends#opt_send`),
            # when the receiver is of one of its classes. A traced program
            # sends each, so its events fire.
            entry, globals = OPT_ENTRIES.fetch(node.name)
            classes = globals.map { |g| @kern.zr_global(@kern.const_get(g)) }
            lambda do |r, argc, av, blk|
              if r.nobits?(7) && r > @qnil && classes.include?(Memory.word(r + @basic_klass))
                @kern.public_send(entry, r, name, argc, av, mode)
              else
                send.call(r, argc, av, blk)
              end
            end
          end

          # A send through the site's cell `at`, tested here first as a
          # binary's site tests it (`Sends#cached_send`): if the receiver's
          # class and the site stamp are the cell's, call the cell's
          # function (a function of the walker runs with no call through the
          # host); else the kernel's send, which fills a cell.
          def cached_send(at, mid, mode)
            lambda do |recv, argc, av, blk|
              klass = if recv & 1 == 1 then @integer
                      elsif recv.nobits?(7) && recv > @qnil then Memory.word(recv + @basic_klass)
                      else @kern.zr_class_of(recv)
                      end
              unless Memory.word(at + @cc_klass) == klass && Memory.word(at + @cc_stamp) == Memory.word(@site_stamp)
                next @kern.zr_send_cached(at, recv, mid, argc, av, blk, mode)
              end

              fn = Memory.word(at + @cc_fn)
              entry = Memory.word(at + @cc_entry)
              found = Memory.word(at + @cc_found)
              body = @host.body_at(fn)
              body ? @host.pin(body.call(recv, argc, av, entry, blk, found)) : @kern::Method.call(fn, recv, argc, av, entry, blk, found)
            end
          end

          # In the core, `recv.send(:name, ...)` is rb_funcall in CRuby's C: a
          # direct call of `name`, private permitted, and never a class's own
          # `send` (`Sends#kernel_send?`).
          def kernel_send?(node, s)
            return false unless s.internal? && %i[send __send__].include?(node.name)

            first = node.args.first
            first.is_a?(Hir::Literal) && first.value.is_a?(Symbol) && !%i[send __send__ public_send].include?(first.value)
          end

          # The call that a kernel send makes, one per site (`Sends#funcall`).
          def funcall(node)
            @funcall_of[node] ||= node.dup.tap do |n|
              n.name = node.args.first.value
              n.args = node.args.drop(1)
              @funcalls[n] = true
            end
          end

          # Gives the task the refinements that are active at the send
          # (`Sends#activate`): those of the `using` entry, or in a `refine`
          # block those of the owner.
          def activate(using, f)
            using == :owner ? @kern.zr_activate_owner(f.rec) : @kern.zr_activate(using)
          end

          # The code of `recv name arg` without a send, as a binary's site
          # answers it (`Arith#operator`): two fixnums under a clear gate
          # (the core ignores the gates, as ruby's C does); in the core, `==`
          # and `!=` of the values that CRuby's C compares natively, and
          # `<=>` of two fixnums while Integer#<=> is ruby's own. The code
          # answers nil when the send must run; it is nil when no path
          # applies to `name`.
          def operator(name, s, operands = [])
            native = native_operators?(s)
            fixnum = FIXNUM_OPS[name]
            float = float_op(name, native, operands)
            compares = native && %i[== != <=>].include?(name)
            return unless fixnum || float || compares

            gate = fixnum ? @kern.const_get(fixnum.first) : 0
            calc = fixnum&.last
            cmp_gate = @kern::GATE_CMP
            lambda do |recv, arg|
              if calc && (recv & arg & 1) == 1 && (native || (@host.gates & gate).zero?)
                case (r = calc.call(recv >> 1, arg >> 1))
                when true then return @qtrue
                when false then return @qfalse
                when FIXNUM then return (r << 1) | 1
                end
              end
              v = float&.call(recv, arg)
              return v if v
              return unless compares

              case name
              when :==, :!=
                kind = @kern.zr_native_eq_kind(recv, arg)
                bool(name == :== ? kind == 1 : kind != 1) unless kind.zero?
              when :<=>
                ((((recv >> 1) <=> (arg >> 1)) << 1) | 1) if (recv & arg & 1) == 1 && (@host.gates & cmp_gate).zero?
              end
            end
          end

          # `recv name arg` on doubles (`Arith#float_path`): both operands
          # are flonums, or one is a flonum and the other a fixnum (within
          # 2**53 for a comparison), and the gates are clear. A site whose
          # `operands` has an Integer literal in a sum, a difference or a
          # comparison has no flonum path (`Arith#float_path?`).
          def float_op(name, native, operands)
            return unless (gate = FLOAT_OPS[name])
            return if %i[* /].none?(name) && operands.any? { |n| n.is_a?(Hir::Literal) && n.value.is_a?(Integer) }

            compare = FLOAT_COMPARES.include?(name)
            gates = @kern.const_get(FIXNUM_OPS.fetch(name).first) | @kern.const_get(gate)
            lambda do |recv, arg|
              next unless (recv & 3 == 2 || arg & 3 == 2) && float_number?(recv, compare) && float_number?(arg, compare)
              next unless native || (@host.gates & gates).zero?

              x = recv & 3 == 2 ? @kern.zr_float_value(recv) : (recv >> 1).to_f
              y = arg & 3 == 2 ? @kern.zr_float_value(arg) : (arg >> 1).to_f
              r = x.public_send(name, y)
              compare ? bool(r) : @kern.zr_float_new(r)
            end
          end

          def float_number?(v, exact)
            return true if v & 3 == 2
            return false unless v & 1 == 1

            !exact || ((v >> 1) + (1 << 53)).between?(0, (1 << 54) - 1)
          end

          # Whether a core send of `name` finds the core's own method
          # (`Sends#core_send?`): any name but PROTOCOL, and `each` except in
          # a method marked `:sends_each`, where ruby's C sends it by name, and
          # an operator, as `native_operators?` says.
          def core_send?(name, s)
            return false unless s.internal?
            return native_operators?(s) if Hir::CoreDef::SENT_OPS.include?(name)

            name == :each ? !(s.def_node && attributes(s.def_node).include?(:sends_each)) : !PROTOCOL.include?(name)
          end

          # Whether the scope answers the core's operators natively
          # (`Arith#native_operators?`): core code outside a method that
          # CRuby writes in Ruby (`Primitive.attr! :ruby`) or whose C sends its
          # operators by name (`:sends_ops`).
          def native_operators?(s) = s.internal? && !(s.def_node && attributes(s.def_node).intersect?(%i[ruby sends_ops]))

          # A call of a block's function (`Block.call`).
          def call_block(pr, argc, av, blk)
            fn = Memory.word(pr + @proc_fn)
            body = @host.body_at(fn) or return @kern::Block.call(fn, pr, argc, av, blk)

            @host.pin(body.call(pr, argc, av, blk))
          end

          # The code of positional arguments: their codes, or, with a Splat,
          # the code of one Array.
          #: (Array[Hir::node] nodes, Scope s) -> [Array[untyped], untyped]
          def arguments(nodes, s)
            return [nodes.map { |a| code(a, s) }, nil] unless nodes.any?(Hir::Splat)

            none = [] #: Array[untyped]
            [none, gather(nodes, s)]
          end

          # The result of a send that a literal block goes with (`site` is the
          # block's): a `break` out of the block ends here.
          def sent(f, site, r)
            return r if r != @qundef
            raise UNWIND, cause: nil unless site

            check(@kern.zr_catch_break(f.rec, site))
          end

          # The code of a send's block. The site's refinements are active
          # when `&value` becomes a Proc, so `&:name` and a refined `to_proc`
          # use them.
          def block_arg(block, s, site = nil)
            case block
            when nil then constant(@qnil)
            when Hir::BlockPass
              value = code(block.value, s)
              using = site&.using
              lambda do |f|
                v = value.call(f)
                activate(using, f) if using
                check(@kern.zr_block_pass(v))
              end
            when Hir::Block then block_image(block, s)
            end
          end

          # The code of a block literal: an RProc image in the slot area, as
          # the lowering makes in the caller's record (FL_STACK). A callee
          # that keeps it copies it to the heap (`zr_block_proc`).
          def block_image(node, s)
            fn, m = block_fn(node, s)
            size = k::RProc.size
            flags = k::T_PROC | k::FL_ALLOCATED | k::FL_STACK
            klass = @kern.zr_global(k::G_PROC)
            site = @sites[node]
            spread = node.params.spread? ? 1 : 0
            inner = s.kind == :block
            lambda do |f|
              p = f.stack.take(size)
              serial = @kern.zr_frame_serial(f.rec)
              ret_home, ret_serial = if inner && !lambda_proc?(f.proc)
                                       [Memory.word(f.proc + @proc_ret_home), Memory.word(f.proc + @proc_ret_serial)]
                                     else
                                       [f.rec, serial]
                                     end
              Memory.set_words(p, [flags, klass, fn, m, f.env || 0, f.self_, f.cref, f.blk, f.rec, serial, site,
                                   ret_home, ret_serial, spread, 0, 0])
              p
            end
          end

          # Whether the Proc `pr` is a lambda: its `lambda` field, which the
          # kernel's layout names as Kernel#lambda is named.
          def lambda_proc?(pr) = Memory.word(pr + @proc_lambda) != 0

          # The function of the block `node`: `(proc, argc, argv, blk) =>
          # Value`, and its FrameMeta. Its body compiles when it first runs.
          def block_fn(node, s)
            @fns[node] ||= begin
              unit = s.unit
              homes = [node, *s.homes]
              kind = unit.internal ? k::KIND_HIDDEN : k::KIND_BLOCK
              open = open?(node, :block, unit, node.params)
              # A program's block in a scope that reads `$~` keeps that scope's
              # `$~` (`Lower::Function#reads_backref?`).
              backref = !unit.internal && Hir.backref_read?(homes.last.respond_to?(:body) ? homes.last.body : homes.last)
              m = meta(node, unit, kind, parent: s.meta, params: node.params, locals: node.locals, open: open, cover: node.cover,
                                         reads_backref: backref)
              k::FrameMeta[m].captures = captures_table(node, homes, unit.spelling)
              inner = scope(node, unit, :block, m, scopes: [node.locals, *s.scopes], homes: homes, def_node: s.def_node, params: node.params,
                                                   open: open)
              # The body compiles at its first run.
              run = nil #: untyped
              fn = @host.callable(lambda do |pr, argc, argv, blk|
                run ||= block_body(node, inner)
                outer = @host.pin(Memory.word(pr + @proc_env))
                # A block's frame names its Proc as its entry, as a binary's
                # does, so a send in a refined Proc finds its refinements
                # (zr_frame_refined_list).
                enter(inner, Memory.word(pr + @proc_self), Memory.word(pr + @proc_cref), Memory.word(pr + @proc_blk),
                      proc: pr, outer: outer, entry: pr, defined: blk) do |f|
                  run.call(f, argc, argv, blk)
                end
              end)
              k::FrameMeta[m].fn = fn
              [fn, m]
            end
          end

          # The code of a block's run: its parameters bound, then its body.
          # A `redo` in the block throws its meta (`Hir::Redo`), and runs
          # the body again from its `Hir::RedoPoint`: a `for` loop binds its
          # variable before that point, and a `redo` does not bind it again.
          def block_body(node, s)
            bind = block_binder(node.params, s)
            before, after = redo_split(node.body)
            head = before && code(before, s)
            body = code(after, s)
            jumps = jumps?([node.body, node.params])
            again = redoes?(node.body) && s.meta
            lambda do |f, argc, argv, blk|
              run_body(s, f, jumps, node) do
                bind.call(f, argc, argv, blk)
                opened(s, f, :block)
                head&.call(f)
                again ? redoable(again) { body.call(f) } : body.call(f)
              end
            end
          end

          # A block's body as `[before, after]` its `Hir::RedoPoint`, or
          # `[nil, body]` when it has none.
          def redo_split(body)
            at = body.is_a?(Hir::Seq) ? body.stmts.index { |stmt| stmt.is_a?(Hir::RedoPoint) } : nil
            return [nil, body] unless at

            [Hir::Seq.new(body.stmts.take(at), body.line), Hir::Seq.new(body.stmts.drop(at + 1), body.line)]
          end

          # The captures table of the block `node` (`Lower#captures_table`):
          # each outer local with its flags (1: the block writes it, 2: its
          # scope binds it more than once), in the order of the program's
          # `spelling`. A Ractor reads it.
          def captures_table(node, homes, spelling)
            rows = Hir::Locals.captures(node).sort_by { |name, _, _| spelling.index(name) }
            words = rows.flat_map do |name, depth, written|
              home = homes[depth]
              counts = home.respond_to?(:body) ? Hir::Locals.assignments(home.body) : Hash.new(0)
              home.params.names.each { |n| counts[n] += 1 } if home.respond_to?(:params) && home.params
              [id(name), (written ? 1 : 0) | (counts[name] > 1 ? 2 : 0)]
            end
            words.push(id(:yield), 4) if Hir::Locals.yields?(node)
            table([words.size / 2, *words])
          end

          def lambda_node(node, s)
            image = block_image(node.block, s)
            ->(f) { slots(f) { check(@kern.zr_proc_lambda(image.call(f))) } }
          end

          def yield_node(node, s)
            args, splat = arguments(node.args, s)
            kwargs = node.kwargs && hash(node.kwargs, s)
            word = line_word(node, s)
            # The core yields through the kernel, which polls the scheduler;
            # a program calls the block's function (`Control#block_call`).
            internal = s.internal?
            lambda do |f|
              list = splat&.call(f)
              plain = splat ? nil : args.map { |a| a.call(f) }
              kw = kwargs&.call(f)
              slots(f) do
                values = plain || elements(list)
                values += [kw] if kw
                av = argv(f, values)
                argc = values.size
                argc = @kern.zr_kw_argc_yield(argc, av) if kw
                argc = @kern.zr_kw_ruby2_out_yield(argc, av) if list && !kw
                line!(f, word)
                if internal || f.blk == @qnil
                  check(@kern.zr_yield(f.blk, argc, av))
                else
                  check(call_block(f.blk, argc, av, @qnil))
                end
              end
            end
          end

          def primitive(node, s)
            return constant(@qnil) if node.name == :attr!
            return local_get(node.args.first.value, 0, s) if node.name == :arg!

            args = node.args.map { |a| code(a, s) }
            name = node.name
            unless node.block
              return ->(_) { check(@kern.public_send(name)) } if args.empty?

              return lambda do |f|
                values = args.map { |a| a.call(f) }
                slots(f) { check(@kern.public_send(name, *values)) }
              end
            end

            image = block_image(node.block, s)
            site = @sites[node.block]
            lambda do |f|
              values = args.map { |a| a.call(f) }
              slots(f) { sent(f, site, @kern.public_send(name, *values, image.call(f))) }
            end
          end

          # `super(args)`. A bare `super` in a block, which the builder
          # expanded, first asks whether `define_method` made the block a
          # method: ruby refuses that.
          def super_node(node, s)
            word = line_word(node, s)
            in_block = node.in_block
            args, splat = arguments(node.args, s)
            kwargs = node.kwargs && hash(node.kwargs, s)
            block = node.block && block_arg(node.block, s)
            site = node.block.is_a?(Hir::Block) ? @sites[node.block] : nil
            at = cell(node, :sc, k::SuperCache.size)
            using = node.using
            lambda do |f|
              if in_block
                line!(f, word)
                check(@kern.zr_zsuper_in_block(f.rec))
              end
              list = splat&.call(f)
              plain = splat ? nil : args.map { |a| a.call(f) }
              kw = kwargs&.call(f)
              slots(f) do
                blk = block ? block.call(f) : f.blk
                values = plain || elements(list)
                values += [kw] if kw
                av = argv(f, values)
                argc = values.size
                argc = @kern.zr_kw_argc(argc, av) if kw
                argc = @kern.zr_kw_ruby2_out(argc, av) if splat && !kw
                line!(f, word)
                activate(using, f) if using
                r = @kern.zr_super(at, f.rec, argc, av, blk)
                @task_refine.call(task, @qnil) if using
                sent(f, site, r)
              end
            end
          end

          # A bare `super` that the builder could not expand into a Super with
          # the method's parameters: no def encloses it. The kernel raises.
          def zsuper(node, s)
            word = line_word(node, s)
            lambda do |f|
              line!(f, word)
              check(@kern.zr_zsuper_outside(f.rec))
            end
          end

          # The code of a send that the walker makes, `recv.name(*values)`,
          # as a lambda of the Frame, the receiver and the values. `kind`
          # names its cell at `node`. An op-assign's sends (`using`) see the
          # refinements of its `using` entry, and a `when`'s `===` those of
          # its `case`; both are sends of the scope (`core`), which a core
          # scope makes to its own methods.
          # @rbs node: untyped
          # @rbs s: Scope
          # @rbs name: Symbol
          # @rbs kind: Symbol
          # @rbs mode: Integer
          # @rbs using: Hir::using
          # @rbs core: bool
          # @rbs return: ^(Frame, Integer, Array[Integer]) -> untyped
          def sender(node, s, name, kind, mode: 0, using: nil, core: true)
            mode |= SEND_CORE if core && core_send?(name, s)
            mode |= SEND_USING if using
            at = cell(node, kind, k::CallCache.size * 4)
            mid = id(name)
            # The site's cell first, as `cached_send` tests it: a hit makes
            # no call into the kernel. Refinements go through the kernel.
            send = cached_send(at, mid, mode)
            lambda do |f, recv, values|
              slots(f) do
                if using
                  activate(using, f)
                  r = @kern.zr_send_cached(at, recv, mid, values.size, argv(f, values), @qnil, mode)
                  @task_refine.call(task, @qnil)
                else
                  r = send.call(recv, values.size, argv(f, values), @qnil)
                end
                check(r)
              end
            end
          end

          # `!x`: nil, false and true answer here while no class redefines
          # `!` (the gate GATE_NOT; the core ignores the gates); any other
          # value gets the send (Lower::Function::Arith#negate).
          def negate(node, s)
            value = code(node.value, s)
            internal = s.internal?
            gate = @kern::GATE_NOT
            word = line_word(node, s)
            send = sender(node, s, :!, :not, mode: 2, core: false)
            lambda do |f|
              v = value.call(f)
              next bool(!truthy?(v)) if (v | 28) == 28 && (internal || (@host.gates & gate).zero?)

              line!(f, word)
              args = [] #: Array[Integer]
              send.call(f, v, args)
            end
          end
        end
      end
    end
  end
end
