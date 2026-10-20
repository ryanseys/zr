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

      # The flags that take a value: the option that each one sets, and
      # what the value is, for the error when it is missing. `--link` adds
      # to a list; each other flag sets its option.
      VALUES = {
        "-o" => [:output, "a path"], "--output" => [:output, "a path"],
        "--emit" => [:emit, "a kind"], "--target" => [:triple, "a triple"],
        "--path-root" => [:root, "a directory"], "--link" => [:link, "an argument"]
      }.freeze #: Hash[String, [Symbol, String]]

      # The flags that take no value, and the option that each turns on.
      SWITCHES = { "--print-gems" => :print_gems, "--allow-runtime-require" => :runtime_require, "--trace" => :trace }.freeze #: Hash[String, Symbol]

      # The flags that zr also takes in ruby mode (`RubyOptions`).
      RUBY_MODE = %w[--trace --allow-runtime-require].freeze

      module_function

      # The options and words of `run`, `build` or `gems`, as a
      # Hash. For `run`, every word after the input file goes to the program.
      # The values have one type for each key, so the Hash is untyped.
      #: (String command, Array[String] args) -> Hash[Symbol, untyped]
      def parse(command, args)
        opts = { args: [], link: [] } #: Hash[Symbol, untyped]
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
        when :link then opts[:link] << value
        else opts[field] = value
        end
      end

      # Whether the build arms the program's trace events: `--trace`, or
      # `ZR_TRACE=1` when the flag is absent.
      #: (Hash[Symbol, untyped] opts) -> bool
      def trace?(opts) = opts[:trace] || Config.current.trace?

      # The gems that a compile reads, as ruby finds them: a Gemfile's lock
      # when BUNDLE_GEMFILE names one, else the gems installed on rubygems'
      # path, with the versions that `source`'s literal `gem` calls ask for
      # (lib/zr/gem_set.rb).
      #: (String source) -> GemSet
      def gem_set(source)
        require_relative "../gem_set"
        GemSet.resolve(requests: GemSet.requests(source))
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
          unless opts[:output]
            # A file that is not there is the first thing to fix.
            Errors.file!(opts[:input])
            Errors.usage_error("missing -o <path>", command)
          end
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
