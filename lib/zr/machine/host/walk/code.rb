# frozen_string_literal: true

module Zr
  module Machine
    class Host
      class Walk
        # The code of each HIR node: a lambda of the running Frame that
        # returns the node's Value. A node is compiled once, when the code
        # of its scope is first needed, so a run does none of the work that
        # depends only on the tree: the dispatch on the node's class, the
        # lookup of a local's slot, a site's cell, a name's id, a send's
        # mode. A def's and a block's body compile when they first run.
        #
        # A form that the walker does not run compiles to code that raises
        # `Unsupported` when it runs, as a branch that never runs never
        # did.
        module Code
          # @type instance: Walk
          # The ivars of Walk that this module reads (walk.rb):
          # @rbs @host: Host
          # @rbs @kern: untyped
          # @rbs @qnil: Integer
          # @rbs @qtrue: Integer
          # @rbs @qfalse: Integer
          # @rbs @qundef: Integer
          # @rbs @ensure_path: Symbol
          # @rbs @jump_line: Integer?
          # @rbs @sites: Hash[untyped, Integer]
          # @rbs @cells: Hash[untyped, Hash[Symbol, Integer]]
          # @rbs @once: Hash[untyped, untyped]
          # @rbs @tables: Hash[Array[Integer], Integer]
          # @rbs @boot_classes: Hash[Symbol, Integer]
          # @rbs @record: Integer
          # @rbs @env_slots: Integer
          # @rbs @env_parent: Integer
          # @rbs @ary_ptr: Integer
          # @rbs @ary_len: Integer

          private

          def code(node, s)
            case node
            when nil then constant(@qnil)
            when Hir::Seq then seq(node, s)
            when Hir::Literal then literal(node, s)
            when Hir::PathLiteral
              text = literal(node.literal, s)
              ->(f) { @kern.zr_path_str(text.call(f)) }
            when Hir::Send then send_node(node, s)
            when Hir::Local then local_get(node.name, node.depth, s)
            when Hir::Assign then local_set(node.name, node.depth, s, code(node.value, s))
            when Hir::SelfRef then SELF
            when Hir::ConstRead then const_read(node, s)
            when Hir::ConstWrite then const_write(node, s)
            when Hir::ConstOrWrite then const_or_write(node, s)
            when Hir::FrozenString then frozen_string(node, s)
            when Hir::If then if_node(node, s)
            when Hir::And then and_node(node, s)
            when Hir::Or then or_node(node, s)
            when Hir::Not then negate(node, s)
            when Hir::While then while_loop(node, s)
            when Hir::Def then define(node, s)
            when Hir::ClassDef, Hir::ModuleDef then class_body(node, s)
            when Hir::SingletonClassDef then singleton_class_body(node, s)
            when Hir::Return then do_return(node, s)
            when Hir::Break then do_break(node, s)
            when Hir::Next then do_next(node, s)
            when Hir::ArrayLit then array(node, s)
            when Hir::HashLit then hash(node, s)
            when Hir::RangeLit then range(node, s)
            when Hir::Interp then interp(node, s)
            when Hir::IvarRead then ivar_read(node, s)
            when Hir::IvarWrite then ivar_write(node, s)
            when Hir::GvarRead then gvar_read(node, s)
            when Hir::GvarWrite then gvar_write(node, s)
            when Hir::CvarRead then cvar_read(node, s)
            when Hir::CvarWrite then cvar_write(node, s)
            when Hir::Yield then yield_node(node, s)
            when Hir::Begin then begin_node(node, s)
            when Hir::MultiAssign then multi_assign(node, s)
            when Hir::Case then case_node(node, s)
            when Hir::Alias then alias_node(node, s)
            when Hir::AliasValue then alias_value(node, s)
            when Hir::Undef then undef_node(node, s)
            when Hir::UndefValue then undef_value(node, s)
            when Hir::GvarAlias then gvar_alias(node, s)
            when Hir::Super then super_node(node, s)
            when Hir::ZSuper then zsuper(node, s)
            when Hir::Lambda then lambda_node(node, s)
            when Hir::Core then core_class(node)
            when Hir::Defined then defined(node, s)
            when Hir::RegexpLit then regexp(node)
            when Hir::RegexpOnce then regexp_once(node, s)
            when Hir::BackRef then back_ref(node)
            when Hir::IndexOpAssign then index_op_assign(node, s)
            when Hir::AttrOpAssign then attr_op_assign(node, s)
            when Hir::KwSplatElement then kw_element(node, s)
            when Hir::Once then once(node, s)
            when Hir::Stop then stop(node)
            when Hir::ExtInit then raise ::NotImplementedError, "#{node.path}: a C extension runs only in a binary"
            when Hir::Trace then trace(node, s)
            when Hir::Cover then cover(node, s)
            when Hir::Using then using(node, s)
            when Hir::UsingDefaults then using_defaults(node)
            when Hir::Activations then activations(node)
            when Hir::Retry then ->(_) { raise RetryJump }
            when Hir::Redo then redo_node(s)
            when Hir::RedoPoint then constant(@qnil)
            when Hir::Require then require_unit(node, s)
            when Hir::Autoload then autoload_unit(node, s)
            else unsupported("#{s.unit.file}:#{line_of(node)}: the walker does not run a #{node.class.name.split("::").last}")
            end
          end

          # The code of `self`.
          SELF = :self_.to_proc

          def constant(v) = ->(_) { v }

          # The code of a send's receiver: `recv`'s, or `self` for none.
          def receiver(recv, s) = recv ? code(recv, s) : SELF

          def unsupported(message) = ->(_) { raise Unsupported, message }

          # A pending unwind in the task is QUNDEF from the kernel: the code
          # raises `Unwind` until a handler takes it.
          def check(v)
            raise UNWIND, cause: nil if v == @qundef

            v
          end

          def truthy?(v) = (v & ~@qnil) != 0
          def bool(b) = b ? @qtrue : @qfalse

          # The pins after `mark` go: the Values that a statement held.
          def drop_pins(pins, mark)
            pins.slice!(mark, pins.size - mark) if pins.size > mark
          end

          def seq(node, s)
            codes = node.stmts.map { |stmt| code(stmt, s) }
            return codes.first || constant(@qnil) if codes.size <= 1

            last = codes.size - 1
            lambda do |f|
              pins = f.stack.pins
              # A continuation (`callcc`) restores the machine stack, not
              # the locals of Ruby frames, so this loop keeps its place in a
              # C iterator: under YJIT, Array#each is Ruby.
              value = nil
              codes.each_index do |i|
                mark = pins.size
                value = codes[i].call(f)
                drop_pins(pins, mark) if i < last
              end
              value
            end
          end

          # --- literals ---

          def literal(node, s)
            v = node.value
            case v
            when Integer
              return constant((v << 1) | 1) if v.bit_length < 63

              text = v.to_s
              site = @sites[node]
              bytes = @host.bytes(text)
              ->(_) { check(@kern.zr_big_literal(site, bytes, text.bytesize)) }
            when Float
              bits = [v].pack("E").unpack1("q<")
              ->(_) { @kern.zr_float_from_bits(bits) }
            when String then string_literal(v, node.chilled && !s.internal? ? :zr_str_new_chilled : :zr_str_new)
            when Symbol then constant(sym(v))
            when nil then constant(@qnil)
            when true then constant(@qtrue)
            when false then constant(@qfalse)
            else unsupported("a literal #{v.class}")
            end
          end

          def string(text)
            bytes = text.b
            k.zr_str_new(@host.bytes(bytes), bytes.bytesize)
          end

          # The code of a String literal, made by the kernel's `fn` with the
          # file's script encoding (`Expressions#string_literal`).
          def string_literal(text, fn)
            bytes = text.b
            ptr = @host.bytes(bytes)
            size = bytes.bytesize
            kern = @kern
            return ->(_) { kern.public_send(fn, ptr, size) } if text.encoding == ::Encoding::UTF_8

            fn = :"#{fn}_at"
            index = ENCODING_INDEX.fetch(text.encoding)
            ->(_) { kern.public_send(fn, ptr, size, index) }
          end

          # ruby's own index for an encoding, which a String holds.
          ENCODING_INDEX = ::Encoding.list.each_with_index.to_h.freeze

          def frozen_string(node, _s)
            bytes = node.value.b
            case node.shared
            when true then shared_literal(node, bytes)
            when false then string_literal(node.value, :zr_str_literal_shared)
            when :uminus
              literal = string_literal(node.value, :zr_str_literal_uminus)
              ->(f) { check(literal.call(f)) }
            else
              literal = string_literal(node.value, :zr_str_literal_freeze)
              ->(f) { check(literal.call(f)) }
            end
          end

          # The one shared frozen String of a UTF-8 literal, which the site's
          # first run makes and keeps in the site's word
          # (`Expressions#shared_literal`). Later runs read the word.
          def shared_literal(node, bytes)
            at = cell(node, :str, 8)
            ptr = @host.bytes(bytes)
            size = bytes.bytesize
            kern = @kern
            lambda do |_|
              word = Memory.word(at)
              word.zero? ? kern.zr_str_literal_cell(at, ptr, size) : word
            end
          end

          def regexp(node)
            src = node.source.b
            site = @sites[node]
            ptr = @host.bytes(src)
            encoding = node.pinned ? ::Encoding.list.index(node.pinned) : -1
            ->(_) { check(@kern.zr_regexp_literal(site, ptr, src.bytesize, node.options, encoding)) }
          end

          def regexp_once(node, s)
            site = @sites[node]
            value = code(node.value, s)
            lambda do |f|
              v = @kern.zr_regexp_once(site)
              v == @qnil ? @kern.zr_regexp_once_set(site, value.call(f)) : v
            end
          end

          def range(node, s)
            low = code(node.low, s)
            high = code(node.high, s)
            excl = node.exclusive ? 1 : 0
            return ->(f) { check(@kern.zr_range_new(low.call(f), high.call(f), excl)) } unless node.static

            site = @sites[node]
            ->(f) { check(@kern.zr_range_literal(site, low.call(f), high.call(f), excl)) }
          end

          def array(node, s)
            build = if node.elements.any?(Hir::Splat)
                      gather(node.elements, s)
                    else
                      values = node.elements.map { |e| code(e, s) }
                      lambda do |f|
                        list = values.map { |v| v.call(f) }
                        slots(f) { @kern.zr_ary_of(list.size, argv(f, list)) }
                      end
                    end
            node.frozen ? ->(f) { @kern.zr_literal_freeze(build.call(f)) } : build
          end

          # The code of an Array of `parts`; a Splat spreads its value.
          def gather(parts, s)
            steps = parts.map do |part|
              if part.is_a?(Hir::Splat)
                value = code(part.value, s)
                ->(f, ary) { check(@kern.zr_ary_splat(ary, value.call(f))) }
              else
                value = code(part, s)
                ->(f, ary) { @kern.zr_ary_push(ary, value.call(f)) }
              end
            end
            size = parts.size
            lambda do |f|
              ary = @host.pin(@kern.zr_ary_new(size))
              steps.each { |step| step.call(f, ary) }
              ary
            end
          end

          #: (Hir::HashLit node, untyped s) -> ^(untyped) -> untyped
          def hash(node, s)
            steps = node.pairs.each_slice(2).map do |key, value|
              if key.is_a?(Hir::HashSplat)
                splat = code(key.value, s)
                ->(f, h) { check(@kern.zr_hash_update(h, splat.call(f))) }
              else
                k_code = code(key, s)
                v_code = code(value, s)
                ->(f, h) { check(@kern.zr_hash_store(h, k_code.call(f), v_code.call(f))) }
              end
            end
            frozen = node.frozen
            lambda do |f|
              h = @host.pin(@kern.zr_hash_new)
              steps.each { |step| step.call(f, h) }
              frozen ? @kern.zr_literal_freeze(h) : h
            end
          end

          def kw_element(node, s)
            pairs = code(node.pairs, s)
            ->(f) { check(@kern.zr_ary_kw_element(pairs.call(f))) }
          end

          def interp(node, s)
            parts = node.parts.map do |part|
              # A part in another script encoding is a plain literal.
              if part.is_a?(Hir::Literal) && part.value.is_a?(String) && part.value.encoding == ::Encoding::UTF_8
                shared_literal(part, part.value.b)
              else
                code(part, s)
              end
            end
            lambda do |f|
              values = parts.map { |part| part.call(f) }
              slots(f) { check(@kern.zr_str_interp(values.size, argv(f, values))) }
            end
          end

          def core_class(node)
            name = id(node.name)
            ->(_) { check(@kern.zr_core_class(name)) }
          end

          def once(node, s)
            body = code(node.body, s)
            lambda do |f|
              return @once[node] if @once.key?(node)

              @once[node] = body.call(f)
            end
          end

          def stop(node)
            what = node.what.to_s
            ->(_) { check(@kern.zr_unloadable(string(what))) }
          end

          def trace(node, s)
            word = line_word(node, s)
            traced = s.unit.traced
            lambda do |f|
              # A silent ensure body's event fires only on its path, on the
              # line of the jump that runs it (`Hir::Trace#line_on`).
              at = node.line_on(@ensure_path, @jump_line)
              next @qnil unless at

              line!(f, at == node.line ? word : at)
              fire(:line) if traced
              @qnil
            end
          end

          def cover(node, s)
            word = line_word(node, s)
            branch = node.id
            lambda do |f|
              line!(f, word)
              @kern.zr_coverage_branch(branch)
              @qnil
            end
          end

          def using(node, s)
            word = line_word(node, s)
            value = code(node.value, s)
            lambda do |f|
              line!(f, word)
              check(@kern.zr_using_activate(node.id, value.call(f), node.from))
              f.self_
            end
          end

          def using_defaults(node)
            lambda do |_|
              node.rows.each { |row, from| @kern.zr_using_default(row, from) }
              @qnil
            end
          end

          def activations(node)
            lambda do |_|
              @kern.zr_activations_reserve(node.count)
              @qnil
            end
          end

          # --- locals ---

          # The code that finds the Env `depth` scopes out, from a Frame.
          def env_at(depth)
            return :env.to_proc if depth.zero?

            parent = @env_parent
            lambda do |f|
              env = f.outer
              (depth - 1).times { env = Memory.word(env + parent) }
              env
            end
          end

          def local_get(name, depth, s)
            i = s.scopes.fetch(depth).index(name) or return unsupported("no local #{name} at depth #{depth}")
            at = i * 8
            if depth.zero? && !s.open
              at += @record
              return ->(f) { Memory.word(f.rec + at) }
            end

            slots = @env_slots
            env = env_at(depth)
            ->(f) { Memory.word(Memory.word(env.call(f) + slots) + at) }
          end

          # The code that sets a local to `value`'s Value. A store into an
          # Env gets the collector's write barrier, unless the Value is an
          # immediate, as the lowering's `barrier`.
          def local_set(name, depth, s, value)
            store = local_store(name, depth, s)
            ->(f) { store.call(f, value.call(f)) }
          end

          # The code that stores a Value (its second argument) into a local,
          # and returns it.
          #: (Symbol name, Integer depth, Scope s) -> ^(Frame, Integer) -> Integer
          def local_store(name, depth, s)
            i = s.scopes.fetch(depth).index(name) or return ->(_, _) { raise Unsupported, "no local #{name} at depth #{depth}" }
            at = i * 8
            if depth.zero? && !s.open
              at += @record
              return lambda do |f, v|
                Memory.set_word(f.rec + at, v)
                v
              end
            end

            slots = @env_slots
            env_of = env_at(depth)
            lambda do |f, v|
              env = env_of.call(f)
              Memory.set_word(Memory.word(env + slots) + at, v)
              @kern.zr_env_barrier(env, v) unless immediate?(v)
              v
            end
          end

          # Whether `v` is no cell (`zr_special_p`): a write barrier for it
          # has nothing to remember.
          def immediate?(v) = v.anybits?(7) || v == @qfalse || v == @qnil

          # --- constants and variables ---

          def scope_class(scope, s)
            case scope
            when nil then ->(f) { @kern.zr_cref_lexical_class(f.cref) }
            when :top then ->(_) { @kern.zr_global(@kern::G_OBJECT) }
            else code(scope, s)
            end
          end

          def const_read(node, s)
            if node.scope.nil? && s.unit.core && (slot = @boot_classes[node.name])
              return ->(_) { @kern.zr_global(slot) }
            end

            at = cell(node, :cc, k::ConstCache.size)
            name = id(node.name)
            word = line_word(node, s)
            if node.scope.nil?
              entry = s.internal? ? :zr_const_get_cached : :zr_const_read_cached
              return lambda do |f|
                line!(f, word)
                check(@kern.public_send(entry, at, f.cref, name))
              end
            end

            scope = scope_class(node.scope, s)
            entry = s.internal? ? :zr_const_get_at_cached : :zr_const_read_at_cached
            lexical = s.internal? ? :zr_const_get_cached : :zr_const_read_cached
            nil_lexical = node.nil_lexical
            lambda do |f|
              klass = scope.call(f)
              line!(f, word)
              # Hir::ConstRead#nil_lexical: a nil scope reads lexically.
              next check(@kern.public_send(lexical, at, f.cref, name)) if nil_lexical && klass == @qnil

              check(@kern.public_send(entry, at, klass, name))
            end
          end

          def const_write(node, s)
            scope = scope_class(node.scope, s)
            value = code(node.value, s)
            name = id(node.name)
            word = line_word(node, s)
            lambda do |f|
              klass = scope.call(f)
              v = value.call(f)
              line!(f, word)
              check(@kern.zr_const_set(klass, name, v))
              v
            end
          end

          def const_or_write(node, s)
            scope = scope_class(node.scope, s)
            value = code(node.value, s)
            name = id(node.name)
            word = line_word(node, s)
            scoped = node.scope
            lambda do |f|
              klass = scope.call(f)
              line!(f, word)
              v = scoped ? @kern.zr_const_lookup_at(klass, name) : @kern.zr_const_lookup(f.cref, name)
              next v if v != @qundef && truthy?(v)

              v = value.call(f)
              check(@kern.zr_const_set(klass, name, v))
              v
            end
          end

          # The name of an ivar as the core's code sees it: a core file's
          # ivars are hidden from a program, as CRuby's C fields are, unless
          # the file or the method shows them.
          def ivar(name, s)
            return name unless s.internal?
            return name if Hir::VISIBLE_IVARS.include?(s.unit.file)
            return name if s.def_node && attributes(s.def_node).include?(:ivars)

            name.to_s.delete_prefix("@").to_sym
          end

          def ivar_read(node, s)
            name = id(ivar(node.name, s))
            at = cell(node, :ic, k::IvarCache.size)
            ->(f) { check(@kern.zr_ivar_get_cached(f.self_, name, at)) }
          end

          def ivar_write(node, s)
            value = code(node.value, s)
            store = ivar_store(node, s)
            ->(f) { store.call(f, value.call(f)) }
          end

          # The code that stores a Value into the ivar `node` names.
          def ivar_store(node, s)
            name = id(ivar(node.name, s))
            at = cell(node, :ic, k::IvarCache.size)
            word = line_word(node, s)
            lambda do |f, v|
              line!(f, word)
              check(@kern.zr_ivar_set_cached(f.self_, name, v, at))
              v
            end
          end

          def gvar_read(node, s)
            name = node.name
            case name
            when :$! then ->(_) { @kern.zr_errinfo }
            when :$~ then ->(_) { @kern.zr_backref_get }
            when :$_ then ->(_) { @kern.zr_lastline_get }
            when :$< then core_class(Hir::Core.new(:ARGF, node.line))
            else
              gvar = id(name)
              s.internal? ? ->(_) { @kern.zr_gvar_get(gvar) } : ->(_) { check(@kern.zr_gvar_read(gvar)) }
            end
          end

          def gvar_write(node, s)
            value = code(node.value, s)
            store = gvar_store(node.name, s, node.shown, node)
            ->(f) { store.call(f, value.call(f)) }
          end

          HOOKED_GVARS = %i[
            $! $@ $& $` $' $+ $$ $? $* $< $FILENAME $LOAD_PATH $LOADED_FEATURES $-a $-l $-p $-W
            $; $, $/ $\ $stdout $stderr $0 $VERBOSE $. $-i
          ].to_set.freeze

          # The code that stores a Value into the gvar `name`: `$~` and `$_`
          # are the frame's, a hooked one runs its setter, and a program's
          # store checks that it runs in the main Ractor.
          def gvar_store(name, s, shown = nil, node = nil)
            return ->(_, v) { @kern.zr_backref_set(v) } if name == :$~ && s.internal?
            return ->(_, v) { check(@kern.zr_backref_assign(v)) } if name == :$~
            return ->(_, v) { @kern.zr_lastline_set(v) } if name == :$_

            gvar = id(name)
            word = node && line_word(node, s)
            internal = s.internal?
            hooked = !internal && HOOKED_GVARS.include?(name)
            shown_id = id(shown || name)
            lambda do |f, v|
              line!(f, word) if word
              check(@kern.zr_ractor_gvar_check(gvar)) unless internal
              next check(@kern.zr_gvar_hooked(shown_id, gvar, v)) if hooked

              check(@kern.zr_gvar_assign(gvar, v))
            end
          end

          def back_ref(node)
            number = (node.number.to_i << 1) | 1
            lambda do |_|
              m = @kern.zr_backref_get
              next @qnil if m == @qnil

              case node.kind
              when :nth then @kern.zr_match_nth(m, number)
              when :pre then @kern.zr_match_pre(m)
              when :post then @kern.zr_match_post(m)
              when :last then @kern.zr_match_last(m)
              end
            end
          end

          def cvar_read(node, s)
            name = id(node.name)
            word = line_word(node, s)
            lambda do |f|
              line!(f, word)
              check(@kern.zr_cvar_get(f.cref, name))
            end
          end

          def cvar_write(node, s)
            value = code(node.value, s)
            name = id(node.name)
            word = line_word(node, s)
            lambda do |f|
              v = value.call(f)
              line!(f, word)
              check(@kern.zr_cvar_set(f.cref, name, v))
              v
            end
          end

          # --- aliases ---

          def alias_node(node, s)
            new_name = id(node.new_name)
            old_name = id(node.old_name)
            word = line_word(node, s)
            lambda do |f|
              line!(f, word)
              check(@kern.zr_alias(@kern.zr_cref_klass(f.cref), new_name, old_name))
            end
          end

          def alias_value(node, s)
            new_name = code(node.new_name, s)
            old_name = code(node.old_name, s)
            word = line_word(node, s)
            lambda do |f|
              fresh = new_name.call(f)
              old = old_name.call(f)
              line!(f, word)
              check(@kern.zr_alias_value(@kern.zr_cref_klass(f.cref), fresh, old))
            end
          end

          def undef_node(node, s)
            names = node.names.map { |n| id(n) }
            word = line_word(node, s)
            lambda do |f|
              line!(f, word)
              names.each { |n| check(@kern.zr_undef(@kern.zr_cref_klass(f.cref), n)) }
              @qnil
            end
          end

          def undef_value(node, s)
            names = node.names.map { |n| code(n, s) }
            word = line_word(node, s)
            lambda do |f|
              names.each do |n|
                name = n.call(f)
                line!(f, word)
                check(@kern.zr_undef_value(@kern.zr_cref_klass(f.cref), name))
              end
              @qnil
            end
          end

          def gvar_alias(node, s)
            new_name = id(node.new_name)
            old_name = id(node.old_name)
            word = line_word(node, s)
            lambda do |f|
              line!(f, word)
              @kern.zr_gvar_alias(new_name, old_name)
              @qnil
            end
          end

          # --- the slot area ---

          # Runs the block with the slots it takes given back after.
          #: [T] (Frame f) { () -> T } -> T
          def slots(f)
            stack = f.stack
            top = stack.top
            begin
              yield
            ensure
              stack.top = top
            end
          end

          # `values` as an argument vector in the slot area, which the caller
          # gives back when the call returns (`slots`).
          def argv(f, values)
            return 0 if values.empty?

            p = f.stack.take(values.size * 8)
            Memory.set_words(p, values)
            p
          end

          # A zeroed cell of `bytes` for one site and kind.
          #: (untyped node, Symbol kind, Integer bytes) -> Integer
          def cell(node, kind, bytes)
            kinds = @cells[node]
            unless kinds
              kinds = {} #: Hash[Symbol, Integer]
              @cells[node] = kinds
            end
            kinds[kind] ||= Memory.zeroed(bytes, 8)
          end

          # A static table of words: `[count, ids...]` and the like.
          def table(words)
            @tables[words] ||= begin
              addr = Memory.zeroed([words.size * 8, 8].max, 8)
              Memory.set_words(addr, words) unless words.empty?
              addr
            end
          end

          def id_table(names) = table([names.size, *names.map { |n| id(n) }])

          # The elements of an Array as Values.
          def elements(ary) = Memory.words(Memory.word(ary + @ary_ptr), Memory.word(ary + @ary_len))
        end
      end
    end
  end
end
