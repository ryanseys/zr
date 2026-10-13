# frozen_string_literal: true

require_relative "../version"
require_relative "../config"
require_relative "errors"

module Zr
  module CLI
    # What `zr help` prints: the list of commands, short (`SHORT`, for
    # `zr -h`) or long (`USAGE`), and one page for each command (`PAGES`).
    module Help
      # The last column of a line of the usage. `ruby -h` keeps its lines
      # below 80 columns and fits in 25 rows; `ruby --help` keeps them to 80
      # (test/ruby/test_rubyoptions.rb).
      WIDTH = 79

      # A row of a table of the usage: `left` in the first 30 columns, then
      # `text` wrapped to WIDTH below it. A `left` too wide for its column
      # puts `text` on the next line.
      #: (String left, String text) -> String
      def self.row(left, text)
        indent = " " * 30
        head = left.size > 26 ? "  #{left}\n#{indent}" : format("  %-28s", left)
        "#{head}#{text.scan(/\S.{0,#{WIDTH - indent.size - 1}}(?=\s|\z)/).join("\n#{indent}")}\n"
      end
      private_class_method :row

      COMMANDS = [
        row("run <file.rb> [args...]", "compile a program, run it, then delete the build"),
        row("build <file.rb> -o <out>", "compile a program to a binary, a WASI module or an object (`compile` is another name)"),
        row("gems [<file.rb>]", "list the gems of a build and their sources"),
        row("inspect <binary>", "print the gems that a binary was built with"),
        row("diff <file.rb> [args...]", "run a program in ruby and as a zr binary; compare"),
        row("doctor", "check this host: ruby, targets, wasmtime, OpenSSL, gems, cache"),
        row("cache [path|size|clean]", "show or clean the build cache"),
        row("version", "print the version"),
        row("help [<command>]", "print help for zr or for one command")
      ].join.freeze #: String

      # The settings: each flag with what it takes, then what it does.
      SETTINGS = Config::SETTINGS.map { |setting| row(Config.usage(setting), setting.about) }.join.freeze #: String

      LINES = <<~TEXT.chomp.freeze
        Usage: zr <command> [options]
               zr [ruby switches] [--] [<file.rb> | -] [args...]

        Commands:
        #{COMMANDS}
      TEXT

      # What `zr -h` prints: the commands, in one screen.
      SHORT = <<~TEXT.freeze
        #{LINES}
        Any other first word runs zr as a ruby, with ruby's switches: zr -e 'p 1'
        -h prints this text; use --help for settings and more.
      TEXT

      # What `zr --help` and `zr help` print: the commands, ruby mode, the
      # settings and the exit statuses.
      USAGE = <<~TEXT.freeze
        #{LINES}
        Any other first word runs zr as a ruby, with ruby's switches (-e, -n,
        -p, -I, -r, -w and the others): `zr app.rb args`, `zr -e 'p 1'`, or a
        program on standard input. A command's name always wins: run a script
        named like one as `zr ./build`.

        Settings, before the command or right after its name. Each one also
        reads its variable (--jobs reads ZR_JOBS); the flag wins:
        #{SETTINGS}
        Exit status: 0 success; 1 error; 2 usage error or a bad setting;
        3 zr does not support the program, the target or this ruby; 130 Ctrl-C.
        `zr run` exits with the program's status.
        Environment variables: reference/environment-variables.md in the docs at
        #{DOCS_URL}
      TEXT

      # The words that ask for help.
      FLAGS = %w[-h --help].freeze

      OUTPUT = "  -o, --output <path>    write the output to <path>\n"
      PRINT_GEMS = "  --print-gems           print the gems that the output was built with\n"
      # The options that choose the gems of a build.
      GEMS = <<~TEXT.gsub(/^/, "  ") #: String
        --gem <name>=<version|dir>
                               use this gem in place of the Gemfile.lock's or zr's
                               own: an installed version, or a directory with a
                               gemspec or lib/; once for each gem
        --gemfile <path>       read the gems of <path>'s lock before zr's own, as
                               `bundle exec ruby` does (BUNDLE_GEMFILE also names it)
        --allow-runtime-require
                               let a require in the program's files that zr cannot
                               find wait for the run time (the binary then carries
                               the compiler to compile what it finds then)
        --trace                arm the trace events in the program's code, for a
                               TracePoint that it reaches by a computed name
                               (ZR_TRACE=1 does the same)
      TEXT
      OPTIONS = <<~TEXT.sub("  -h, --help", "#{GEMS}  -h, --help") #: String
        Options:
          --emit <kind>          binary (the default), obj, or wasm
          --target <triple>      build for <triple>: aarch64-apple-darwin,
                                 aarch64-linux-musl or wasm32-wasi (`zr doctor`
                                 shows what this host can build)
          --path-root <dir>      write source paths in the output as <dir> plus the
                                 path below zr's root or the working directory,
                                 so that two checkouts make the same bytes
          --link <arg>           give <arg> to the system linker (cc) for a native
                                 binary: an object, an archive, -framework <name>,
                                 -Wl,<flags>; once for each argument
          -h, --help             print this help
      TEXT

      PAGES = {
        "run" => <<~TEXT,
          Usage: zr run [options] <file.rb> [args...]

          Compiles <file.rb>, runs it with [args...], then deletes the build.
          Every word after <file.rb> goes to the program. With --emit wasm,
          wasmtime runs the module.

          #{OPTIONS.sub("binary (the default), obj, or wasm", "binary (the default) or wasm")}
        TEXT
        "build" => <<~TEXT,
          Usage: zr build [options] <file.rb> -o <out>

          Compiles <file.rb> with the zr runtime. The output is a native
          binary, a WASI module (--emit wasm, or a wasm32 --target) or an
          object file (--emit obj).

          #{OPTIONS.sub("Options:\n", "Options:\n#{OUTPUT}#{PRINT_GEMS}")}
        TEXT
        "doctor" => <<~TEXT,
          Usage: zr doctor

          Checks what zr needs on this host, and prints ok, warn or fail for
          each: the ruby version, the host, wasmtime, OpenSSL 3, the standard
          library and the cache. A `target` line for each target gives the
          outputs that zr makes for it (binary, obj, wasm), and the outputs
          that this host can make. Exits with status 1 if a check fails.
        TEXT
        "gems" => <<~TEXT,
          Usage: zr gems [--gem <name>=<version|dir>]... [--gemfile <path>] [--json] [<file.rb>]

          Lists each gem that a build can read, with its version and its
          source: stdlib (ruby's own library, in zr), port (a gem with a C
          part that zr ports), Gemfile.lock, or --gem. With <file.rb>, lists
          only the gems that the build of <file.rb> reads.

          --json                 print JSON, one object for each gem
          --target <triple>      the target of the build of <file.rb>
        TEXT
        "inspect" => <<~TEXT,
          Usage: zr inspect [--json] <binary>

          Prints the gems that zr built <binary> with, from the manifest that
          each binary, object and WASI module carries: the zr and ruby
          versions, the target, and each gem with its version and source.
        TEXT
        "diff" => <<~TEXT,
          Usage: zr diff [options] <file.rb> [args...]

          Runs <file.rb> with [args...] under ruby and as a zr binary, and
          compares stdout, stderr, the exit status and the signal. Prints
          the kind of difference (same, output-diff, exception-diff,
          status-diff, crash, timeout, refused or build-error), then a diff
          of each part. Exits with status 0 when the two are the same, 1 when
          they differ, 2 when the build failed, and 3 when zr refused it.

          ruby reads the same --gem directories, and runs as `bundle exec
          ruby` does with --gemfile or BUNDLE_GEMFILE. The two runs can
          differ where ruby has other versions of its gems than zr: see
          `zr gems`.

          #{OPTIONS.sub(/^  --emit .*\n/, "")}
        TEXT
        "version" => <<~TEXT,
          Usage: zr version

          Prints zr's version and the ruby version that it matches:
          zr #{VERSION} (for ruby #{RUBY_PIN}). `zr --version` and `zr -v` do the same.
        TEXT
        "help" => <<~TEXT,
          Usage: zr help [<command>]

          Prints the commands of zr, or the help of one command.
          `zr <command> --help` does the same.
        TEXT
        "cache" => <<~TEXT
          Usage: zr cache [path|size|clean [--days N | --all]]

          path            print the cache directory (the default)
          size            what the cache holds, by kind
          clean           delete the files that this zr does not use
          clean --days N  the same, but keep the files used in the last N days
          clean --all     delete every file in the cache, also this zr's own;
                          the next build makes them again

          An installed zr also cleans its cache when it grows past
          ZR_CACHE_MAX_GB (default 5).
        TEXT
      }.freeze #: Hash[String, String]

      module_function

      # Prints the page of `command`. For nil, prints the list of commands:
      # the long one, or with `long: false` the short one.
      #: (?String? command, ?long: bool) -> void
      def show(command = nil, long: true)
        return puts(long ? USAGE : SHORT) if command.nil?

        Errors.usage_error("unknown command '#{command}'") unless PAGES.key?(command)
        puts PAGES.fetch(command)
      end

      # Whether the options before the first word of `args` ask for help.
      #: (Array[String] args) -> bool
      def asked?(args) = args.take_while { |word| word.start_with?("-") }.intersect?(FLAGS)

      # Whether `word` is one edit (a letter added, removed, changed, or
      # two letters swapped) from `name`.
      #: (String word, String name) -> bool
      def near?(word, name)
        return false if (word.size - name.size).abs > 1

        a, b = [word, name].sort_by(&:size) #: [String, String]
        i = 0
        i += 1 while i < a.size && a[i] == b[i]
        return a[i..] == b[(i + 1)..] if a.size < b.size

        a[(i + 1)..] == b[(i + 1)..] || (a[i] == b[i + 1] && a[i + 1] == b[i] && a[(i + 2)..] == b[(i + 2)..])
      end
    end
  end
end
