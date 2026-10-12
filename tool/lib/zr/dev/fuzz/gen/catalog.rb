# frozen_string_literal: true

module Zr
  module Dev
    module Fuzz
      module Gen
        # The methods that the `explore` pack calls (as Fuzzilli's
        # ExplorationMutator does): any public method that a core class or
        # one of its core modules defines, read from the running ruby (the
        # pinned ruby), with arguments from a small pool. Most calls
        # raise; the class and the message of the error are compared too.
        module Catalog
          CLASSES = { int: Integer, float: Float, str: String, sym: Symbol, ints: Array, strs: Array, hash: Hash,
                      range: Range }.freeze

          # The arguments of a call: one of each kind, and some edges.
          ARGS = ["0", "1", "-1", "2", "3", '"a"', '"ab"', ":a", "nil", "true", "[1, 2]", "{ a: 1 }", "1.5", "(1..3)", '"%d"',
                  "(2**64)", "Float::NAN", '""', "[]"].freeze

          # Methods whose answer changes from run to run (a hash value, a
          # random pick), that print in their own way (pretty_print needs pp),
          # or that differ from ruby on purpose (the order of names).
          BLOCKED = %i[hash shuffle shuffle! sample crypt pretty_print pretty_print_cycle pretty_print_inspect
                       pretty_print_instance_variables pretty_inspect display].freeze

          module_function

          # The sorted names of the methods for each type: the ones that the
          # class or a module of its own ancestors (below Object) owns.
          NAMES = CLASSES.transform_values do |klass|
            owners = klass.ancestors.take_while { |a| a != Object }
            klass.public_instance_methods(true).select { |m| owners.include?(klass.instance_method(m).owner) }
                 .reject { |m| BLOCKED.include?(m) }.sort.freeze
          end.freeze

          def names(type) = NAMES.fetch(type)

          def pick(type, rng) = names(type).sample(random: rng)

          # How many arguments a call passes: what the method takes, and
          # now and then one more or one less, to reach its ArgumentError.
          def arg_count(type, name, rng)
            arity = CLASSES.fetch(type).instance_method(name).arity
            required = arity.negative? ? -arity - 1 : arity
            count = arity.negative? ? rng.rand(required..(required + 2)) : required
            count += pick_offset(rng)
            count.clamp(0, 4)
          end

          def pick_offset(rng)
            roll = rng.rand
            return 1 if roll < 0.05
            return -1 if roll < 0.1

            0
          end
        end
      end
    end
  end
end
