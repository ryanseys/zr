# frozen_string_literal: true

module Zr
  module Machine
    class Host
      class Walk
        # The code that binds a def's or a block's arguments to its
        # parameters, as `Lower::Function::Params` emits it: the keywords
        # out of the argument vector, the arity check, the positional
        # parameters, the defaults, the keywords and the block.
        module Arguments
          private

          # The code that binds a def's `argc` arguments at `argv` in its
          # Frame. `fn` is the def's function: a `ruby2_keywords` method is
          # known by it (`zr_kw_undeclared`).
          def method_binder(p, s, fn)
            plain_binder(p, s) || general_binder(p, s, fn)
          end

          # The code that binds only required parameters, each a name of its
          # own: they are the scope's first locals, so the argument vector is
          # copied to them as it is.
          def plain_binder(p, s)
            names = p.required
            return unless p.plain? && names.all?(Symbol) && names.uniq.size == names.size && s.locals.first(names.size) == names

            arity = arity_check(p)
            block = block_store(p, s)
            at = @record
            slots = @env_slots
            open = s.open
            lambda do |f, argc, argv|
              t = task
              kw = @task_kw.call(t)
              unless kw.zero?
                @task_set_kw.call(t, 0)
                argc = @kern.zr_kw_undeclared(kw, argc, argv, 0)
              end
              arity.call(argc)
              if open
                env = f.env
                values = Memory.words(argv, argc)
                Memory.set_words(Memory.word(env + slots), values)
                values.each { |v| @kern.zr_env_barrier(env, v) unless immediate?(v) }
              else
                Memory.copy(f.rec + at, argv, argc * 8)
              end
              block&.call(f, f.blk)
            end
          end

          def general_binder(p, s, fn)
            positional = positional_binder(p, s)
            keywords = keywords?(p) ? keywords_binder(p, s) : nil
            arity = arity_check(p)
            block = block_store(p, s)
            rest_fn = p.rest && p.rest != :implicit ? fn : 0
            lambda do |f, argc, argv|
              t = task
              kw = @task_kw.call(t)
              @task_set_kw.call(t, 0)
              kwhash = nil
              if keywords
                if kw > 1
                  argc = @kern.zr_kw_tab_in(kw, argc, argv)
                  kw = 1
                end
                if kw == 1
                  argc -= 1
                  kwhash = Memory.word(argv + (argc * 8))
                end
              elsif kw != 0
                argc = @kern.zr_kw_undeclared(kw, argc, argv, rest_fn)
              end
              args = Memory.words(argv, argc)
              arity.call(args.size)
              positional.call(f, args)
              keywords&.call(f, kwhash)
              block&.call(f, f.blk)
            end
          end

          # The code that binds a block's arguments. A proc's parameters
          # take what they get (`loose`); a lambda's are a method's.
          def block_binder(p, s)
            positional = positional_binder(p, s)
            relaxed = loose_binder(p, s)
            keywords = keywords?(p) ? keywords_binder(p, s) : nil
            arity = arity_check(p)
            block = block_store(p, s)
            rest_fn = p.rest && p.rest != :implicit
            nothing = p.names.empty? && p.plain?
            spread = p.spread?
            spread_kind = p.optional.empty? ? 1 : 2
            node = s.node
            lambda do |f, argc, argv, blk|
              strict = lambda_proc?(f.proc)
              t = task
              kw = @task_kw.call(t)
              @task_set_kw.call(t, 0)
              kwhash = nil
              if keywords
                argc = @kern.zr_kw_tab_in(kw, argc, argv) if kw > 1
                if kw != 0
                  argc -= 1
                  kwhash = Memory.word(argv + (argc * 8))
                end
              elsif kw != 0
                argc = @kern.zr_kw_undeclared(kw, argc, argv, rest_fn ? @fns[node].first : 0)
              end
              next arity.call(argc) if nothing && strict

              arity.call(argc) if strict
              if spread && !strict
                out = f.stack.take(16)
                n = check(@kern.zr_block_args(argc, argv, spread_kind, out, out + 8))
                argc = n >> 1
                argv = Memory.word(out)
              end
              args = Memory.words(argv, argc)
              (strict ? positional : relaxed).call(f, args)
              keywords&.call(f, kwhash)
              block&.call(f, blk)
            end
          end

          def keywords?(p) = p.keywords.any? || !p.kwrest.nil?

          # The code that checks a count of arguments against the
          # parameters, and raises ArgumentError for a wrong one.
          def arity_check(p)
            min = p.required.size + p.post.size
            max = p.rest && p.rest != :implicit ? -1 : min + p.optional.size
            required = p.keywords.select { |_, d| d.nil? }.map(&:first)
            names = required.empty? ? 0 : id_table(required) + 8
            lambda do |given|
              next if given >= min && (max.negative? || given <= max)

              check(@kern.zr_wrong_arity_kw(given, min, max, names, required.size))
            end
          end

          # The code that binds `&block` to the Proc of the block given.
          def block_store(p, s)
            return unless p.block && owns?(p, p.block, [:block, 0])

            store = local_store(p.block, 0, s)
            ->(f, blk) { store.call(f, @kern.zr_block_proc(blk)) }
          end

          # The code of a lambda's or a method's positional parameters:
          # required parameters from the front, post parameters from the
          # back, then the optional ones in order, then the rest.
          def positional_binder(p, s)
            front = p.required.size
            back = p.post.size
            optional = p.optional.size
            required, post = required_binds(p, s)
            defaults = optional_binder(p, s)
            rest = rest_store(p, s)
            lambda do |f, args|
              n = args.size
              front.times { |i| required[i]&.call(f, i < n ? args[i] : @qnil) }
              post_at = [n - back, front].max
              given = (n - front - back).clamp(0, optional)
              defaults&.call(f, args, front, given)
              if rest
                start = front + given
                rest.call(f, args[start...[post_at, start].max] || [])
              end
              back.times { |i| post[i]&.call(f, post_at + i < n ? args[post_at + i] : @qnil) }
            end
          end

          # The code of a proc's parameters: missing ones are nil, extra ones
          # are dropped.
          def loose_binder(p, s)
            front = p.required.size
            back = p.post.size
            optional = p.optional.size
            required, post = required_binds(p, s)
            defaults = optional_binder(p, s)
            rest = rest_store(p, s)
            has_rest = p.rest && p.rest != :implicit
            lambda do |f, args|
              given = (args.size - front - back).clamp(0, optional)
              front.times { |i| required[i]&.call(f, args.fetch(i, @qnil)) }
              defaults&.call(f, args, front, given)
              start = front + given
              post_at = has_rest ? [args.size - back, start].max : start
              rest&.call(f, args[start...post_at] || [])
              back.times { |i| post[i]&.call(f, args.fetch(post_at + i, @qnil)) }
            end
          end

          # The code that binds each required and each post parameter, or
          # nil for one that a repeated `_` before it owns.
          def required_binds(p, s)
            front = p.required.size
            required = p.required.each_with_index.map { |t, i| first?(p, t, i) ? target_bind(t, s) : nil }
            post = p.post.each_with_index.map { |t, i| first?(p, t, front + i) ? target_bind(t, s) : nil }
            [required, post]
          end

          # The code that binds the rest parameter to an Array of its
          # arguments.
          def rest_store(p, s)
            return unless p.rest && p.rest != :implicit && owns?(p, p.rest, [:rest, 0])

            store = local_store(p.rest, 0, s)
            ->(f, list) { store.call(f, slots(f) { @kern.zr_ary_of(list.size, argv(f, list)) }) }
          end

          # The code of the optional parameters: a given argument binds its
          # slot, if the slot owns the name; a default is an assignment to
          # the name, as CRuby compiles it, so a repeated `_`'s default
          # reaches the first.
          def optional_binder(p, s)
            return if p.optional.empty?

            steps = p.optional.each_with_index.map do |(name, default), i|
              store = local_store(name, 0, s)
              owned = owns?(p, name, [:opt, i])
              value = code(default, s)
              [owned ? store : nil, ->(f) { store.call(f, value.call(f)) }]
            end
            lambda do |f, args, front, given|
              steps.size.times do |i|
                given_store, default = steps[i]
                if i < given
                  given_store&.call(f, args[front + i])
                else
                  default.call(f)
                end
              end
            end
          end

          # The code that binds a positional parameter, a name or a
          # destructuring `(a, b)`, to a Value.
          def target_bind(target, s)
            return local_store(target, 0, s) unless target.is_a?(Hir::MultiTarget)

            spread = multi(target, s)
            ->(f, v) { spread.call(f, v, Assign::UNSTAGED) }
          end

          # Whether the parameter `target` at position `i` of the required
          # and post parameters is the first of its name: a repeated `_`
          # binds its first argument, as in ruby.
          def first?(p, target, i) = owns?(p, target, i < p.required.size ? [:req, i] : [:post, i - p.required.size])

          # Whether the parameter at `slot` (`[kind, index]`) owns the name
          # `name`: it is the first parameter of that name, in ruby's order.
          def owns?(p, name, slot)
            return true unless name.is_a?(Symbol)

            owners = (@owners ||= {}.compare_by_identity)[p] ||= begin
              slots = [*p.required.each_index.map { |i| [[:req, i], p.required[i]] },
                       *p.optional.each_index.map { |i| [[:opt, i], p.optional[i][0]] },
                       [[:rest, 0], p.rest], *p.post.each_index.map { |i| [[:post, i], p.post[i]] },
                       *p.keywords.each_index.map { |i| [[:key, i], p.keywords[i][0]] }, [[:kwrest, 0], p.kwrest], [[:block, 0], p.block]]
              slots.reverse.to_h { |at, owner| [owner, at] }
            end
            owners[name] == slot
          end

          # The code that binds the keyword parameters from the keywords
          # Hash (nil when the call gave none).
          def keywords_binder(p, s)
            ids = p.keywords.map(&:first)
            required = p.keywords.select { |_, d| d.nil? }.map(&:first)
            required_table = id_table(required) + 8
            ids_table = id_table(ids) + 8
            keys = p.keywords.each_with_index.map do |(name, default), i|
              [id(name), default && code(default, s), owns?(p, name, [:key, i]) ? local_store(name, 0, s) : nil]
            end
            kwrest = p.kwrest
            rest = kwrest && kwrest != :nokey && owns?(p, kwrest, [:kwrest, 0]) ? local_store(kwrest, 0, s) : nil
            lambda do |f, kwhash|
              hash = kwhash || @qnil
              check(@kern.zr_kw_missing(hash == @qnil ? @kern.zr_hash_new : hash, required_table, required.size)) unless required.empty?
              check(@kern.zr_kw_unknown(hash, ids_table, ids.size)) if kwrest.nil? && hash != @qnil
              keys.each do |name, default, store|
                v = hash == @qnil ? @qundef : @kern.zr_kw_get(hash, name)
                v = default ? default.call(f) : @qnil if v == @qundef
                store&.call(f, v)
              end
              next if kwrest.nil?

              if kwrest == :nokey
                check(@kern.zr_kw_none(hash))
              else
                v = hash == @qnil ? @kern.zr_hash_new : check(@kern.zr_kw_rest(hash, ids_table, ids.size))
                rest&.call(f, v)
              end
            end
          end
        end
      end
    end
  end
end
