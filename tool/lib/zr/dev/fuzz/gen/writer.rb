# frozen_string_literal: true

module Zr
  module Dev
    module Fuzz
      # The generator of `zr-dev fuzz`: it writes a Ruby program from a
      # seed. A program is valid by construction (as YARPGen's are): each
      # expression has a type that the writer knows, and reads only the
      # locals of its scope that have that type. Ruby has no undefined
      # behavior, so the only dangers are a program that does not stop, a
      # program too big for the machine, and a program whose output
      # changes from run to run. The writer keeps loops bounded and sizes
      # small, and never prints an object id, a hash value, the time or an
      # unseeded random number.
      #
      # A program is a prelude of helpers, the definitions of the packs
      # that are on (classes, methods, refinements), then 15 to 40 units,
      # and sometimes an ending (an uncaught exception, exit, at_exit).
      # Each unit runs in a block that rescues and prints any error, so a
      # unit that raises costs only itself, and the message of the error
      # is compared too. Each value prints with a label (`u3.2: [1, 2]`),
      # so a difference names its unit.
      module Gen
        # The types of values that the writer knows.
        #
        #   int float str sym bool    the scalars
        #   ints strs                 an Array of Integers, of Strings
        #   hash                      a Hash of String or Symbol keys to Integers
        #   range                     a finite Range of Integers
        #   proc                      a Proc or lambda of one Integer to an Integer
        TYPES = %i[int float str sym bool ints strs hash range proc].freeze

        # The locals of one scope, by type. A block's scope sees its
        # parent's locals; a method's does not.
        class Scope
          def initialize(parent = nil)
            @parent = parent
            @vars = {}
          end

          def bind(name, type) = @vars[name] = type

          def of(type)
            mine = @vars.select { |_, t| t == type }.keys
            @parent ? @parent.of(type) + mine : mine
          end

          def names = (@parent ? @parent.names : []) + @vars.keys
        end

        class Writer
          include Values
          include Statements
          include Packs

          attr_reader :rng, :swarm

          # The prelude of every program. `__unit` rescues StandardError and
          # ScriptError (NotImplementedError, a refusal at run time), never
          # Exception: an exit or an interrupt must stay what it is.
          PRELUDE = <<~RUBY
            def __show(label, value) = puts("\#{label}: \#{value.inspect}")
            def __opaque(x) = x
            def __unit(name)
              yield
            rescue StandardError, ScriptError => e
              puts "\#{name}: \#{e.class}: \#{e.message}"
            end
          RUBY

          def initialize(seed, only: nil)
            @seed = seed
            @rng = Random.new(seed)
            @swarm = Swarm.new(@rng, only: only)
            @count = 0
            @scope = Scope.new
            @tops = []
            @requires = []
            @unit = 0
            @shown = 0
            @defs = []
            @classes = []
          end

          # The program's source.
          def program
            setup_packs
            units = Array.new(rng.rand(15..40)) { unit }
            ending = swarm.on?("ending") && chance?(0.5) ? ending_code : nil
            head = "# zr-dev fuzz gen --seed #{@seed} (#{swarm.packs.join(", ")})\n"
            [head, *@requires.uniq.map { "require \"#{_1}\"\n" }, PRELUDE, *@tops.map { "#{_1}\n" },
             *units.map { "#{_1}\n" }, ending && "#{ending}\n"].compact.join
          end

          # One unit: a block of statements with a new scope.
          def unit
            @unit += 1
            @shown = 0
            body = scoped { Array.new(rng.rand(2..7)) { statement(3) }.join("\n") }
            "__unit(\"u#{@unit}\") do\n#{indent(body)}\nend"
          end

          # --- helpers ---

          def chance?(p) = rng.rand < p
          def pick(list) = list.sample(random: rng)
          def int(range) = rng.rand(range)
          def fresh(prefix = "v") = "#{prefix}#{@count += 1}"
          def label = "u#{@unit}.#{@shown += 1}"
          def indent(text, by = 1) = text.gsub(/^(?=.)/, "  " * by)

          # Picks one of `choices`: [weight, value] pairs, where a value
          # may be a lambda that gives the result.
          def weighted(choices)
            choices = choices.select { |w, _| w.positive? }
            roll = rng.rand * choices.sum(&:first)
            _, choice = choices.find { |w, _| (roll -= w) <= 0 } || choices.last
            choice.respond_to?(:call) ? choice.call : choice
          end

          # Runs the block in a new scope (a block's), and returns its value.
          def scoped(parent: @scope)
            outer = @scope
            @scope = Scope.new(parent)
            yield
          ensure
            @scope = outer
          end

          # Binds a new local of `type`, and returns its name.
          def bind(type, name = fresh)
            @scope.bind(name, type)
            name
          end

          def local(type) = pick(@scope.of(type))

          # A top-level definition (a class, a method), written before
          # the units.
          def top(code) = @tops << code

          def require!(lib) = @requires << lib
        end
      end
    end
  end
end
