# frozen_string_literal: true

require_relative "../target"
require_relative "errors"
require_relative "help"

module Zr
  module CLI
    # The options of `run`, `build` and `gems`.
    #
    # The parser is a small table, not OptionParser: optparse requires
    # `pp`, which calls eval, and a compiler that zr compiles would then
    # have to include eval support.
    module Options
      EMITS = { "binary" => nil, "obj" => "obj", "wasm" => "wasm" }.freeze #: Hash[String, String?]

      # What `--gem` takes.
      GEM_VALUE = "<name>=<version> or <name>=<dir>, for example --gem csv=3.3.6"

      # The flags that take a value: the option that each one sets, and
      # what the value is, for the error when it is missing. `--link` and
      # `--gem` add to a list; each other flag sets its option.
      VALUES = {
        "-o" => [:output, "a path"], "--output" => [:output, "a path"],
        "--emit" => [:emit, "a kind"], "--target" => [:triple, "a triple"],
        "--path-root" => [:root, "a directory"], "--link" => [:link, "an argument"],
        "--gem" => [:gems, GEM_VALUE], "--gemfile" => [:gemfile, "a path"]
      }.freeze #: Hash[String, [Symbol, String]]

      # The flags that take no value, and the option that each turns on.
      SWITCHES = { "--print-gems" => :print_gems, "--allow-runtime-require" => :runtime_require, "--trace" => :trace }.freeze #: Hash[String, Symbol]

      # The flags that zr also takes in ruby mode (`RubyOptions`).
      RUBY_MODE = %w[--trace --allow-runtime-require --gem --gemfile].freeze

      module_function

      # The options and words of `run`, `build` or `gems`, as a
      # Hash. For `run`, every word after the input file goes to the program.
      # The values have one type for each key, so the Hash is untyped.
      #: (String command, Array[String] args) -> Hash[Symbol, untyped]
      def parse(command, args)
        opts = { args: [], link: [], gems: [] } #: Hash[Symbol, untyped]
        until args.empty?
          word = args.shift
          if opts[:input] && command == "run"
            opts[:args] << word
            next
          end
          name, value = word.start_with?("--") && word.include?("=") ? word.split("=", 2) : [word, nil] #: Array[String?]
          if (taken = VALUES[name])
            field, what = taken
            set(opts, field, value || args.shift || Errors.usage_error("#{name} needs #{what}", command), command)
            next
          end
          if (switch = SWITCHES[name])
            opts[switch] = true
            next
          end

          case name
          when "--" then opts[:input] ? opts[:args].concat(args.shift(args.size)) : (opts[:input] = args.shift)
          when "-h", "--help"
            Help.show(command)
            exit
          when /\A-./ then Errors.usage_error("unknown option '#{word}'", command)
          else
            opts[:input] ? opts[:args] << word : opts[:input] = word
          end
        end
        check(command, opts)
      end

      # Sets the option `field` to `value`, or adds it to the option's list.
      #: (Hash[Symbol, untyped] opts, Symbol field, String value, String command) -> void
      def set(opts, field, value, command)
        case field
        when :gems then opts[:gems] << gem_flag(value, command)
        when :link then opts[:link] << value
        else opts[field] = value
        end
      end

      # Whether the build arms the program's trace events: `--trace`, or
      # `ZR_TRACE=1` when the flag is absent.
      #: (Hash[Symbol, untyped] opts) -> bool
      def trace?(opts) = opts[:trace] || Config.current.trace?

      # `--gem NAME=VERSION` or `--gem NAME=DIR`, as [name, value].
      #: (String? word, String command) -> [String, String]
      def gem_flag(word, command)
        name, value = word.to_s.split("=", 2)
        if value.to_s.empty? || !name.to_s.match?(/\A[\w.-]+\z/)
          Errors.usage_error("--gem needs #{GEM_VALUE}", command)
        end
        # The check above stops the build when `value` is nil.
        [name, value] #: [String, String]
      end

      # The gems that a compile reads before zr's standard library: the
      # `--gem` flags, then the Gemfile.lock of `--gemfile` or
      # BUNDLE_GEMFILE (lib/zr/gem_set.rb).
      #: (Hash[Symbol, untyped] opts) -> GemSet
      def gem_set(opts)
        require_relative "../gem_set"
        GemSet.resolve(opts[:gems], gemfile: opts[:gemfile])
      rescue GemSet::Unresolved => e
        abort "zr: #{e.message}"
      end

      #: (String command, Hash[Symbol, untyped] opts) -> Hash[Symbol, untyped]
      def check(command, opts)
        return check_gems(opts) if command == "gems"

        Errors.usage_error("missing <file.rb>", command) unless opts[:input]
        if opts[:emit] && !EMITS.key?(opts[:emit])
          Errors.usage_error("unknown --emit '#{opts[:emit]}'; use binary, obj or wasm", command)
        end
        Errors.usage_error("--path-root needs an absolute path", command) if opts[:root] && !opts[:root].start_with?("/")
        Errors.usage_error("--print-gems applies only to 'zr build'", command) if opts[:print_gems] && command != "build"
        if command == "run"
          Errors.usage_error("-o does not apply; use 'zr build' to keep the output", command) if opts[:output]
          Errors.usage_error("cannot run an object file; use 'zr build --emit obj'", command) if opts[:emit] == "obj"
        else
          Errors.usage_error("missing -o <path>", command) unless opts[:output]
          dir = File.dirname(opts[:output])
          Errors.usage_error("-o #{opts[:output]}: the directory #{dir} does not exist", command) unless File.directory?(dir)
          Errors.usage_error("unexpected argument '#{opts[:args].first}'", command) unless opts[:args].empty?
        end
        opts[:emit] = EMITS[opts[:emit]]
        opts
      end

      # `zr gems` takes the options that choose the gems, and at most one file.
      #: (Hash[Symbol, untyped] opts) -> Hash[Symbol, untyped]
      def check_gems(opts)
        Errors.usage_error("-o does not apply", "gems") if opts[:output]
        Errors.usage_error("unexpected argument '#{opts[:args].first}'", "gems") unless opts[:args].empty?
        opts[:emit] = EMITS[opts[:emit]]
        opts
      end

      # The target that `--target` gives. `--emit wasm` alone means
      # wasm32-wasi.
      #: (String? triple, String? emit, String command) -> Target
      def target_for(triple, emit, command)
        return emit == "wasm" ? Target::WASM32_WASI : Target.default unless triple

        Target.fetch(triple) || Errors.usage_error("unknown target '#{triple}'. The targets are #{Target.all.map(&:triple).join(", ")}", command)
      end
    end
  end
end
