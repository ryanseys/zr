# frozen_string_literal: true

require_relative "../hir/switches"

module Zr
  module CLI
    # ruby's own command line, for `zr` used as a ruby: `zr -e 'p 1'`,
    # `zr -ne 'print if /x/' file`, `zr -Ilib -rapp script.rb args`,
    # `zr - < script.rb`. It reads the switches as ruby.c's proc_options
    # does, in order, and stops at the script's name, at `-` or at `--`.
    #
    # The switches that change the build become `Hir::Switches`: a
    # prelude that sets what each one sets, and prism's options for the
    # main file. The ones that act before the build (-C, -c, -v,
    # --version, -S) are read here and done by `Commands::Compile#ruby`.
    #
    # zr's own flags of `zr run` (--trace, --gem, --gemfile,
    # --allow-runtime-require) can come before the script too.
    class RubyOptions
      # @rbs @warning_categories: Hash[Symbol, bool]
      # @rbs @features: Hash[String, bool]
      # @rbs @record_separator: [String?]?
      # @rbs @output_separator: String?
      # @rbs @field_separator: String?
      # @rbs @inplace: String?
      # @rbs @verbose: [bool?]?
      # @rbs @help: bool
      # @rbs @verbose_option: bool
      # @rbs @loop: bool
      # @rbs @print: bool
      # @rbs @split: bool
      # @rbs @line: bool
      # @rbs @envopt: bool
      # @rbs @rubylib: Array[String]
      # @rbs @backtrace_limit: Integer?
      # @rbs @external_name: String?
      # @rbs @internal_name: String?

      # A command line that ruby rejects. ruby raises a RuntimeError and
      # exits 1: `zr: invalid option -q  (-h will show valid options)
      # (RuntimeError)`.
      class Invalid < StandardError; end

      # The code of each -e, in order. A program with -e has no script.
      attr_reader :inline #: Array[String]
      # The script's name as given, `-` for standard input, or nil for
      # neither (standard input too).
      attr_reader :script #: String?
      # The words after the script, or after -e's code: the program's ARGV.
      attr_reader :args #: Array[String]
      # The directories of -I, as given, and the features of -r.
      attr_reader :includes #: Array[String]
      attr_reader :requires #: Array[String]
      # The directories of -C, in order (each from the one before).
      attr_reader :chdirs #: Array[String]
      # -x, -s, -S, -c, -d, -v, --version and --copyright. (-n, -p, -a
      # and -l go to prism, in `switches`.)
      attr_reader :xflag, :sflag, :search, :check, :debug, :version, :version_only, :copyright #: bool
      # The encodings of -E, -U, -K and --encoding, or nil.
      attr_reader :external, :internal #: String?
      # The source encoding of -K, or nil.
      attr_reader :source_encoding #: String?
      # The words of zr's own flags, for `Options.parse("run", ...)`.
      attr_reader :zr #: Array[String]
      # A switch that zr does not support, and why, or nil.
      attr_reader :refused #: String?
      # The warnings about the switches, which ruby prints once they are
      # read (a command line is read more than once: `CLI.compiles?`).
      attr_reader :warnings #: Array[String]

      # zr's own flags that ruby mode takes, and whether each takes a value.
      OWN_FLAGS = { "--trace" => false, "--allow-runtime-require" => false, "--gem" => true, "--gemfile" => true }.freeze

      # ruby's --enable and --disable features (ruby.c's EACH_FEATURES).
      FEATURES = %w[gems error_highlight did_you_mean syntax_suggest rubyopt frozen_string_literal yjit zjit].freeze
      # -W:name categories.
      CATEGORIES = %w[deprecated experimental performance strict_unused_block].freeze
      # The encodings of -K.
      KCODES = { "e" => "EUC-JP", "s" => "Windows-31J", "u" => "UTF-8", "n" => "ASCII-8BIT", "a" => "ASCII-8BIT" }.freeze

      # The options of `argv`, then those of RUBYOPT and RUBYLIB in `env`.
      # Raises Invalid for a command line that ruby rejects.
      #: (Array[String] argv, ?Hash[String, String?] env) -> RubyOptions
      def self.parse(argv, env = ENV.to_h) = new.tap { |options| options.parse!(argv.dup, env) }

      #: () -> void
      def initialize
        @inline = []
        @script = nil
        @args = []
        @includes = []
        @requires = []
        @chdirs = []
        @loop = @print = @split = @line = @xflag = @sflag = @search = @check = @debug = @version = @version_only = @copyright = false
        @debug_frozen = false
        @external = @internal = @external_name = @internal_name = @source_encoding = nil
        @envopt = false
        @rubylib = []
        @backtrace_limit = nil
        @zr = []
        @refused = nil
        @warnings = []
        @warning_categories = {} #: Hash[Symbol, bool]
        @features = {} #: Hash[String, bool]
        @record_separator = nil
        @output_separator = nil
        @field_separator = nil
        @inplace = nil
        @verbose = nil
        @help = false
        @verbose_option = false
      end

      # Reads the switches, then the script's name and its arguments.
      #: (Array[String] argv, ?Hash[String, String?] env) -> void
      def parse!(argv, env = ENV.to_h)
        switches!(argv)
        @script = argv.shift if @inline.empty?
        # process_options: an empty name is standard input, as "-" is.
        @script = "-" if @script&.empty?
        @args = argv
        rubyopt!(env["RUBYOPT"]) unless @features["rubyopt"] == false
        # ruby_init_loadpath: RUBYLIB's directories, as given, after -I's.
        @rubylib = env["RUBYLIB"].to_s.b.split(File::PATH_SEPARATOR).reject(&:empty?).map { |dir| dir.force_encoding(::Encoding::UTF_8) }
        @warnings << "zr: warning: -K is specified; it is for 1.8 compatibility and may cause odd behavior" if @source_encoding && @verbose == [true]
      end

      # A script whose first line is a `#!` line that does not name ruby
      # runs as with -x: from its first `#!` line that names ruby.
      #: () -> void
      def xflag! = @xflag = true

      # The switches on a script's first line, `#!/usr/bin/env ruby -w`,
      # as ruby reads them: after the first " -" of a line that names
      # ruby. They come after the command line's own.
      #: (String source) -> void
      def shebang!(source)
        line = source.each_line.first.to_s
        return unless line.start_with?("#!") && line.include?("ruby")

        at = line.index(" -") or return
        words = line[(at + 1)..].to_s.split
        switches!(words)
      end

      # The program's text for -e: each -e is one line.
      #: () -> String
      def inline_source = @inline.map { |code| "#{code}\n" }.join

      # Whether ruby runs a program at all: not for -v, --version or
      # --copyright alone.
      #: (bool tty) -> bool
      def runs?(tty)
        return false if @version_only || @copyright
        return true unless @inline.empty? && @script.nil?

        !(@version || tty)
      end

      # -h or --help: zr's usage.
      #: () -> bool
      def help? = @help

      # What `Hir::Switches` the build takes.
      #: () -> Hir::Switches
      def switches
        command_line = +""
        command_line << "p" if @print
        command_line << "n" if @loop
        command_line << "a" if @split
        command_line << "l" if @line
        command_line << "x" if @xflag && @inline.empty?
        # -e's code: prism leaves out the warnings that ruby gives only for
        # a file (a regexp literal in a condition).
        command_line << "e" unless @inline.empty?
        Hir::Switches.new(prelude: prelude, command_line: command_line, frozen_string_literal: @features["frozen_string_literal"],
                          gems: @features.fetch("gems", true), inline: !@inline.empty?, verbose: (verbose = @verbose) ? verbose.first : false,
                          source_encoding: @source_encoding, debug_frozen_string_literal: @debug_frozen)
      end

      # The ruby that sets what the switches set, in ruby's order: the
      # verbosity and the warnings as the options are read, the load path,
      # the separators, the libraries of -r, the globals of -s, then the
      # encodings. nil when no switch sets anything.
      #: () -> String?
      def prelude
        lines = [] #: Array[String]
        verbose = @verbose
        record_separator = @record_separator
        lines << "$VERBOSE = #{verbose.first.inspect}" if verbose
        lines << "$DEBUG = true" if @debug
        @warning_categories.each { |name, on| lines << "Warning[#{name.inspect}] = #{on}" }
        # -I's directories, expanded, then RUBYLIB's as given, each frozen.
        dirs = @includes.map { |dir| File.expand_path(dir) } + @rubylib
        lines << "$LOAD_PATH.unshift(#{dirs.map { |dir| "#{dir.inspect}.freeze" }.join(", ")})" unless dirs.empty?
        # A separator of one byte is binary, as ruby makes it, and frozen.
        if record_separator
          text = record_separator.first
          lines << "$/ = #{text.nil? ? "nil" : "#{text.inspect}#{".b" if text.size == 1}.freeze"}"
        end
        lines << "Primitive.zr_backtrace_limit_set(#{@backtrace_limit})" if @backtrace_limit
        # --disable=did_you_mean: no DidYouMean, and so no suggestion.
        lines << "Object.send(:remove_const, :DidYouMean)" if @features["did_you_mean"] == false
        lines << "$\\ = #{@output_separator.inspect}" if @line
        lines << "$; = Regexp.new(#{@field_separator.inspect})" if @field_separator
        lines << "$-i = ARGF.inplace_mode = #{@inplace.inspect}" if @inplace
        lines << "$-p = true" if @print
        # ruby.c defines chomp, chop, sub and gsub on $_ for -n and -p.
        lines << "Kernel.send(:line_methods)" if @print || @loop
        lines << "$-l = true" if @line
        lines << "$-a = true" if @split
        # ruby runs -r before it reads the main script, so a required file
        # sees none of the script's locals in TOPLEVEL_BINDING.
        unless @requires.empty?
          lines << "Primitive.zr_hidden_set(TOPLEVEL_BINDING, :__before_main__, true)"
          @requires.each { |feature| lines << "require #{feature.inspect}" }
          lines << "Primitive.zr_hidden_set(TOPLEVEL_BINDING, :__before_main__, nil)"
        end
        lines << S_FLAG if @sflag
        lines << "Encoding.send(:store_default, 0, #{@external.inspect})" if @external
        lines << "Encoding.send(:store_default, 1, #{@internal.inspect})" if @internal
        lines << "IO.send(:stdio_encodings)" if @internal
        lines.empty? ? nil : "#{lines.join("\n")}\n"
      end

      # process_sflag: each word of ARGV before the first that does not
      # start with "-" (or after a "--") sets a global: `-x` sets `$x` to
      # true, `-name=value` sets `$name` to "value", and a "-" in the name
      # becomes "_".
      # A name that no global can have stops the program before it starts,
      # as ruby stops: one line with the program's name, and status 1.
      S_FLAG = <<~'RUBY'
        while (word = ARGV.first)&.start_with?("-")
          ARGV.shift
          break if word == "--"

          name, value = word[1..].split("=", 2)
          if name.match?(/[^A-Za-z0-9_-]/)
            $stderr.write("zr: invalid name for global variable - #{word.split("=", 2).first} (NameError)\n")
            exit 1
          end
          Primitive.zr_gvar_set_m(:"$#{name.tr("-", "_")}", value.nil? ? true : value) unless name.empty?
        end
      RUBY

      private

      # The switches of RUBYOPT, after the command line's: only those that
      # change how a program runs (ruby.c's moreswitches with envopt). A
      # word without its "-" gets one.
      #: (String? text) -> void
      def rubyopt!(text)
        return if text.nil?

        # moreswitches: what the command line set stays; RUBYOPT sets only
        # the rest.
        kept = [@external_name, @external, @internal_name, @internal, @source_encoding, @features.dup, @warning_categories.dup, @backtrace_limit]
        @external_name = @external = @internal_name = @internal = @source_encoding = nil
        @envopt = true
        text.split.each do |word|
          word = "-#{word}" unless word.start_with?("-")
          switches!([word])
        end
        external_name, external, internal_name, internal, source_encoding, features, categories, limit = kept
        @external_name, @external = external_name, external if external_name
        @internal_name, @internal = internal_name, internal if internal_name
        @source_encoding = source_encoding if source_encoding
        @features.merge!(features)
        @warning_categories.merge!(categories)
        @backtrace_limit = limit if limit
      ensure
        @envopt = false
      end

      # The letters that RUBYOPT can give.
      ENV_LETTERS = "dEIKrUvwW"

      # proc_options: the switches up to the script's name.
      #: (Array[String] argv) -> void
      def switches!(argv)
        until argv.empty?
          word = argv.first.to_s
          break unless word.start_with?("-") && word.size > 1

          argv.shift
          break if word == "--"

          if word.start_with?("--")
            long!(word[2..].to_s, argv)
          else
            letters!(word[1..].to_s, argv)
          end
        end
      end

      # The letters of one word, `-lane`, each a switch until one that
      # takes the rest of the word or the next word.
      #: (String s, Array[String] argv) -> void
      def letters!(s, argv)
        until s.empty?
          c = s[0].to_s
          s = s[1..].to_s
          raise Invalid, "invalid switch in RUBYOPT: -#{c}" if @envopt && !ENV_LETTERS.include?(c)

          case c
          when "a" then @split = true
          when "p" then @print = @loop = true
          when "n" then @loop = true
          when "d"
            @debug = @debug_frozen = true
            @verbose = [true]
          when "y" then nil # parse.y's debug output: ruby with prism prints none.
          when "v"
            next if @version || @verbose_option

            @version = true
            verbose!
          when "w" then verbose!
          when "W" then s = warning!(s)
          when "c" then @check = true
          when "s" then @sflag = true
          when "h"
            @help = true
            return
          when "l"
            @line = true
            # ruby takes $\ from $/ as -l is read: -0 before -l counts.
            record_separator = @record_separator
            @output_separator = record_separator ? record_separator.first : "\n"
          when "S" then @search = true
          when "e"
            raise Invalid, "no code specified for -e" if s.empty? && argv.empty?

            @inline << (s.empty? ? argv.shift.to_s : s)
            return
          when "r" then return value(s, argv) { |feature| @requires << feature }
          when "I" then return value(s, argv) { |dir| @includes << dir }
          when "i"
            # "" edits in place with no backup.
            @inplace = s
            return
          when "x"
            @xflag = true
            @chdirs << s unless s.empty?
            return
          when "C", "X"
            dir = s.empty? ? argv.shift : s
            raise Invalid, "Can't chdir" if dir.nil? || dir.empty?

            @chdirs << dir
            return
          when "F"
            @field_separator = s unless s.empty?
            return
          when "E"
            text = s.empty? ? argv.shift : s
            raise Invalid, "missing argument for -E" if text.nil?

            return encoding!(text, "-E")
          when "U" then internal_once!("UTF-8")
          when "K"
            kcode = s[0].to_s
            s = s[1..].to_s
            # proc_K_option: the source encoding, and the external one where
            # nothing set that yet.
            if (name = KCODES[kcode.downcase])
              @source_encoding = name
              unless @external_name
                @external_name = name
                @external = known_encoding(name)
              end
            end
          when "0" then s = record_separator!("0#{s}")
          when "\r"
            # A word that ends in a DOS line end's "\r" switches nothing.
            return if s.empty?

            raise Invalid, invalid_option(c)
          else
            raise Invalid, invalid_option(c)
          end
        end
      end

      # How ruby shows a switch that it does not know: a visible character
      # as it is, a control character as its escape, else its byte in hex.
      ESCAPED = { "\0" => "\\0", "\n" => "\\n", "\r" => "\\r", "\t" => "\\t", "\f" => "\\f", "\v" => "\\v",
                  "\b" => "\\b", "\a" => "\\a", "\e" => "\\e", "\x7f" => "\\c?" }.freeze

      #: (String c) -> String
      def invalid_option(c)
        shown = c.match?(/\A[[:graph:]]\z/) ? c : ESCAPED.fetch(c) { format("\\x%.2x", c.getbyte(0).to_i) }
        "invalid option -#{shown}  (-h will show valid options)"
      end

      # The rest of the word, or the next word, given to `block`.
      #: (String s, Array[String] argv) { (String) -> void } -> void
      def value(s, argv)
        given = s.empty? ? argv.shift : s
        yield given if given
      end

      # -v, -w and -W2: $VERBOSE true, and the default categories on.
      #: () -> void
      def verbose!
        @verbose = [true]
        @warning_categories[:deprecated] = true
        @warning_categories[:experimental] = true
      end

      # proc_W_option: -W, -W0, -W1, -W2 or -W:[no-]category. Returns the
      # rest of the word.
      #: (String s) -> String
      def warning!(s)
        if s.start_with?(":")
          name = s[1..].to_s
          on = !name.start_with?("no-")
          name = name.delete_prefix("no-")
          category = CATEGORIES.find { |known| name_match?(known, name) }
          if category
            @warning_categories[category.to_sym] = on
          else
            @warnings << "zr: warning: unknown warning category: '#{name}'"
          end
          return ""
        end
        level = s[/\A[0-7]/]
        s = s[(level ? 1 : 0)..].to_s
        case level&.to_i(8) || 2
        when 0
          @verbose = [nil]
          @warning_categories[:deprecated] = false
          @warning_categories[:experimental] = false
        when 1
          @verbose = [false]
          @warning_categories[:deprecated] = false
        else verbose!
        end
        s
      end

      # proc_0_option: -0 and up to three octal digits more, `s` from the
      # switch's own 0. Returns the rest of the word.
      #: (String s) -> String
      def record_separator!(s)
        digits = s[/\A[0-7]{1,4}/].to_s
        value = digits.to_i(8)
        @record_separator = if value > 0o377 then [nil]
                            elsif value.zero? && digits.size >= 2 then [""]
                            else [value.chr]
                            end
        s[digits.size..].to_s
      end

      # proc_encoding_option: `external[:internal]`.
      #: (String text, String name) -> void
      def encoding!(text, name)
        external, internal, extra = text.split(":", 3)
        raise Invalid, "extra argument for #{name}: #{extra}" if extra && !extra.empty?

        external_once!(external.to_s) unless external.to_s.empty?
        internal_once!(internal.to_s) unless internal.to_s.empty?
      end

      # set_option_encoding_once: an encoding set twice must be the same
      # name, as casecmp compares them.
      #: (String name) -> void
      def external_once!(name)
        given = @external_name
        raise Invalid, "default_external already set to #{given}" if given && !given.casecmp?(name)

        @external_name = name
        @external = known_encoding(name)
      end

      #: (String name) -> void
      def internal_once!(name)
        given = @internal_name
        raise Invalid, "default_internal already set to #{given}" if given && !given.casecmp?(name)

        @internal_name = name
        @internal = known_encoding(name)
      end

      #: (String? name) -> String
      def known_encoding(name)
        found = ::Encoding.find(name.to_s) or raise ArgumentError
        found.name
      rescue ArgumentError
        raise Invalid, "unknown encoding name - #{name}"
      end

      # proc_long_options.
      #: (String s, Array[String] argv) -> void
      def long!(s, argv)
        name, given = s.split("=", 2)
        name = name.to_s
        raise Invalid, "invalid switch in RUBYOPT: --#{name}" if @envopt && !ENV_LONG.match?(name)
        if OWN_FLAGS.key?("--#{name}")
          @zr << "--#{name}"
          @zr << (given || argv.shift || raise(Invalid, "missing argument for --#{name}")) if OWN_FLAGS.fetch("--#{name}")
          return
        end
        case name
        when "copyright" then @copyright = true
        when "version" then @version_only = true
        when "verbose"
          @verbose_option = true
          @verbose = [true]
        when "help" then @help = true
        when "debug", /\Adebug-/
          # --debug=frozen-string-literal, --debug-frozen-string-literal and
          # the like are CRuby's own checks.
          unless given || name != "debug"
            @debug = @debug_frozen = true
            @verbose = [true]
          end
          @debug_frozen = true if given == "frozen-string-literal" || name == "debug-frozen-string-literal"
        when "jit", "yjit", "zjit", /\A[yz]jit-/ then nil # zr compiles ahead of time.
        when "crash-report" then nil
        when "encoding" then encoding!(argument(name, given, argv), "--encoding")
        when "external-encoding" then external_once!(argument(name, given, argv))
        when "internal-encoding" then internal_once!(argument(name, given, argv))
        when "parser"
          parser = argument(name, given, argv)
          refuse("--parser=parse.y (zr parses with prism)") if parser == "parse.y"
          raise Invalid, "unknown parser #{parser}" unless %w[prism parse.y].include?(parser)
        when "dump"
          argument(name, given, argv)
          refuse("--dump")
        when "yydebug" then nil
        when "backtrace-limit"
          limit = argument(name, given, argv)
          raise Invalid, "wrong limit for backtrace length" unless limit.match?(/\A-?\d+\z/) && limit.to_i >= -1

          @backtrace_limit = limit.to_i
        when /\A(enable|disable)(?:-(.+))?\z/
          on = $1 == "enable"
          words = $2 || argument($1.to_s, given, argv)
          words.split(/[\s,]+/).each { |word| feature!(word, on) }
        else
          raise Invalid, "invalid option --#{s}  (-h will show valid options)"
        end
      end

      # The long switches that RUBYOPT can give.
      ENV_LONG = /\A(?:debug|enable|disable|encoding|external-encoding|internal-encoding|backtrace-limit|crash-report|[yz]?jit)(?:-|\z)/

      # The value of a long option: after "=", or the next word. A "=" with
      # nothing after it is a missing value too.
      #: (String name, String? given, Array[String] argv) -> String
      def argument(name, given, argv)
        value = given || argv.shift
        raise Invalid, "missing argument for --#{name}" if value.nil? || value.empty?

        value
      end

      # feature_option: a name, or the start of one, of FEATURES, or
      # "all". An unknown name only warns.
      #: (String word, bool on) -> void
      def feature!(word, on)
        return if word.empty?

        if (name = FEATURES.find { |known| name_match?(known, word) })
          @features[name] = on
        elsif name_match?("all", word)
          FEATURES.each { |known| @features[known] = on }
        elsif !name_match?("jit", word)
          @warnings << "zr: warning: unknown argument for --#{on ? "enable" : "disable"}: '#{word}'"
          @warnings << "zr: warning: features are [#{FEATURES.join(", ")}]."
        end
      end

      # The characters between the words of a name.
      SEPARATORS = %w[- _].freeze

      # ruby.c's name_match_p: `str` names `name` when each of its words is
      # the start of the same word of `name`, a "-" or "_" between them.
      #: (String name, String str) -> bool
      def name_match?(name, str)
        return false if str.empty? || str.size >= name.size + 1

        n = 0
        s = 0
        loop do
          while str[s] && str[s].to_s.downcase == name[n]
            s += 1
            n += 1
            return true if s == str.size
          end
          return false unless SEPARATORS.include?(str[s])

          n += 1 while name[n]&.match?(/[[:alnum:]]/)
          return false unless SEPARATORS.include?(name[n])

          n += 1
          return true if name[n].nil?

          s += 1
          return true if s == str.size
        end
      end

      #: (String what) -> void
      def refuse(what)
        @refused ||= "#{what} is not supported"
      end
    end
  end
end
