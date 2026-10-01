# frozen_string_literal: true

require_relative "../target"
require_relative "errors"
require_relative "help"

module Zr
  module CLI
    # The options of `run`, `build`, `machine` and `gems`.
    #
    # The parser is a small table, not OptionParser: optparse requires
    # `pp`, which calls eval, and a compiler that zr compiles would then
    # have to include eval support.
    module Options
      EMITS = { "binary" => nil, "obj" => "obj", "wasm" => "wasm" }.freeze

      module_function

      # The options and words of `run`, `build`, `machine` or `gems`, as a
      # Hash. For `run`, every word after the input file goes to the program.
      def parse(command, args)
        opts = { args: [], link: [], gems: [] }
        until args.empty?
          word = args.shift
          if opts[:input] && command == "run"
            opts[:args] << word
            next
          end
          name, value = word.start_with?("--") && word.include?("=") ? word.split("=", 2) : [word, nil]
          case name
          when "--" then opts[:input] ? opts[:args].concat(args.shift(args.size)) : (opts[:input] = args.shift)
          when "-h", "--help"
            Help.show(command)
            exit
          when "-o", "--output" then opts[:output] = value || args.shift || Errors.usage_error("#{name} needs a path", command)
          when "--emit" then opts[:emit] = value || args.shift || Errors.usage_error("--emit needs a kind", command)
          when "--target" then opts[:triple] = value || args.shift || Errors.usage_error("--target needs a triple", command)
          when "--path-root" then opts[:root] = value || args.shift || Errors.usage_error("--path-root needs a directory", command)
          when "--link" then opts[:link] << (value || args.shift || Errors.usage_error("--link needs an argument", command))
          when "--gem" then opts[:gems] << gem_flag(value || args.shift, command)
          when "--print-gems" then opts[:print_gems] = true
          when "--allow-runtime-require" then opts[:runtime_require] = true
          when "--gemfile" then opts[:gemfile] = value || args.shift || Errors.usage_error("--gemfile needs a path", command)
          when /\A-./ then Errors.usage_error("unknown option '#{word}'", command)
          else
            opts[:input] ? opts[:args] << word : opts[:input] = word
          end
        end
        check(command, opts)
      end

      # `--gem NAME=VERSION` or `--gem NAME=DIR`, as [name, value].
      def gem_flag(word, command)
        name, value = word.to_s.split("=", 2)
        if value.to_s.empty? || !name.match?(/\A[\w.-]+\z/)
          Errors.usage_error("--gem needs <name>=<version> or <name>=<dir>, for example --gem csv=3.3.6", command)
        end
        [name, value]
      end

      # The gems that a compile reads before zr's standard library: the
      # `--gem` flags, then the Gemfile.lock of `--gemfile` or
      # BUNDLE_GEMFILE (lib/zr/gem_set.rb).
      def gem_set(opts)
        require_relative "../gem_set"
        GemSet.resolve(opts[:gems], gemfile: opts[:gemfile])
      rescue GemSet::Unresolved => e
        abort "zr: #{e.message}"
      end

      def check(command, opts)
        return check_gems(opts) if command == "gems"

        Errors.usage_error("missing <file.rb>", command) unless opts[:input]
        if opts[:emit] && !EMITS.key?(opts[:emit])
          Errors.usage_error("unknown --emit '#{opts[:emit]}'; use binary, obj or wasm", command)
        end
        Errors.usage_error("--path-root needs an absolute path", command) if opts[:root] && !opts[:root].start_with?("/")
        if command == "machine" && (!opts[:gems].empty? || opts[:gemfile])
          Errors.usage_error("--gem and --gemfile do not apply; a machine file requires nothing", command)
        end
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
      def check_gems(opts)
        Errors.usage_error("-o does not apply", "gems") if opts[:output]
        Errors.usage_error("unexpected argument '#{opts[:args].first}'", "gems") unless opts[:args].empty?
        opts[:emit] = EMITS[opts[:emit]]
        opts
      end

      # The target that `--target` gives. `--emit wasm` alone means
      # wasm32-wasi.
      def target_for(triple, emit, command)
        return emit == "wasm" ? Target::WASM32_WASI : Target.default unless triple

        Target.fetch(triple) || Errors.usage_error("unknown target '#{triple}'. The targets are #{Target.all.map(&:triple).join(", ")}", command)
      end
    end
  end
end
