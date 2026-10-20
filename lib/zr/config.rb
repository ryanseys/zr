# frozen_string_literal: true

require "rbconfig"
require_relative "binary"
require_relative "session"
require_relative "error"

module Zr
  # The settings that steer zr, read once. Each one (`SETTINGS`) has a
  # flag on the command line and a `ZR_*` environment variable; the flag
  # wins (`CLI.settings!` takes the flags off the command line).
  # `Config.current` reads them on first use; every later call in the
  # same process gets that same frozen instance, so one build sees one
  # consistent set of settings even if something changes `ENV`
  # afterward. Code reads a `ZR_*` variable only through this class.
  class Config
    # @rbs @given: Hash[String, String]
    # @rbs @env: Hash[String, String] | RBS::Unnamed::ENVClass
    # @rbs @jobs_given: bool
    # @rbs @jobs: Integer?
    # @rbs @eval_mode: String?
    # @rbs @timing: bool
    # @rbs @quiet: bool
    # @rbs @verify: bool
    # @rbs @kernel_checked: bool
    # @rbs @wasm_names: bool
    # @rbs @tune: bool
    # @rbs @run_cache: bool
    # @rbs @trace: bool

    # `ZR_LINKER`: `auto` (zr's own linker, and cc for what it cannot
    # link), `ruby` (zr's linker only) or `cc`. Empty or unset is `auto`.
    LINKERS = %w[auto ruby cc].freeze

    # `ZR_CODE_CACHE`: on, off, or on with a check of each hit.
    CODE_CACHES = %w[1 0 verify].freeze
    # How a build runs a C extension: linked in, its bundle relinked in,
    # or its bundle loaded with dlopen (`Ext::Source#mode`).
    EXT_MODES = %w[static embed dynamic].freeze

    # A `ZR_*` value or a setting's flag that zr cannot use. The message
    # names the variable or the flag, its value, and a value that works.
    # The CLI prints it and exits 2.
    class Invalid < ArgumentError
      include Error
    end

    # @rbs skip -- typed in sig/zr/config.rbs
    Setting = Data.define(:env, :flag, :kind, :values, :about, :steers)

    # A row of `SETTINGS`.
    #: (String env, String flag, :switch | :choice | :value kind, Array[String] | String | nil values, String about, ?steers: bool) -> Setting
    def self.row(env, flag, kind, values, about, steers: true)
      Setting.new(env: env, flag: flag, kind: kind, values: values, about: about, steers: steers)
    end
    private_class_method :row

    # One row for each setting: its variable, its flag, its kind and what
    # the flag takes, and the line of `zr help`. A `:switch` is on or off
    # (`--timing`, `--no-timing`); a `:choice` takes one of its values; a
    # `:value` takes a word that `Config` checks as it reads it
    # (`--jobs=4` or `--jobs 4`). A setting that `steers` changes what a
    # build writes, so the test harness keys a kept binary on it.
    SETTINGS = [
      row("ZR_LINKER", "--linker", :choice, LINKERS, "the macOS linker: auto, ruby (zr's own) or cc"),
      row("ZR_JOBS", "--jobs", :value, "N", "the workers that assemble a large unit (-j N)"),
      row("ZR_EVAL", "--eval-mode", :choice, %w[walk], "walk: eval in a native program walks the tree"),
      row("ZR_TIMING", "--timing", :switch, nil, "print each phase of a build and its seconds", steers: false),
      row("ZR_QUIET", "--quiet", :switch, nil, "print no notice of a long build, and no progress line", steers: false),
      row("ZR_VERIFY", "--verify", :switch, nil, "check each IR function before it is assembled"),
      row("ZR_KERNEL_CHECKED", "--kernel-checked", :switch, nil, "check each operator of the kernel that can wrap"),
      row("ZR_WASM_NAMES", "--wasm-names", :switch, nil, "give a WASI module a name section"),
      row("ZR_WASM_WIDTH", "--wasm-width", :value, "N", "the group size of a big wasm function's dispatch"),
      row("ZR_TUNE", "--tune", :switch, nil, "larger GC limits and YJIT for heavy work (on)"),
      row("ZR_CACHE", "--cache-dir", :value, "DIR", "the cache directory (`zr cache path` prints it)"),
      row("ZR_CACHE_MAX_GB", "--cache-max-gb", :value, "GB", "the most GB an installed zr keeps (5; 0: none)"),
      row("ZR_HOST_RUBY", "--host-ruby", :value, "RUBY", "the ruby that zr runs to resolve gems"),
      row("ZR_LINK_ARGS", "--link-args", :value, "WORDS", "words for the system linker, split as sh does"),
      row("ZR_EXT_OBJECTS", "--ext-objects", :value, "PATH=OBJ,...", "C extensions to link: each a bundle's path, then its objects"),
      row("ZR_EXT", "--ext", :choice, EXT_MODES, "how a C extension runs: static (its objects; a bundle alone embeds), embed or dynamic"),
      row("ZR_NATIVE_EXT", "--native-ext", :value, "GEM[=VERSION],...", "gems whose own C extension to link, not a port"),
      row("ZR_EXT_CONFIG", "--ext-config", :value, "GEM=ARG ...", "the extconf.rb arguments for a gem's C extension"),
      row("ZR_RUN_CACHE", "--run-cache", :switch, nil, "keep the binary of each run and run it again (on)"),
      row("ZR_TRACE", "--trace", :switch, nil, "arm the trace events in the program's code"),
      row("ZR_CODE_CACHE", "--code-cache", :choice, CODE_CACHES, "keep the runtime's code (1), not (0), or check it"),
      row("ZR_DEBUG", "--backtrace", :switch, nil, "show the backtrace of an error that stops zr", steers: false)
    ].freeze #: Array[Setting]

    # The setting of each flag, also `-j` and the `--no-` form of a switch.
    FLAGS = SETTINGS.flat_map do |setting|
      names = setting.kind == :switch ? [setting.flag, setting.flag.sub("--", "--no-")] : [setting.flag]
      names.map { |name| [name, setting] }
    end.to_h.then { |flags| flags.merge("-j" => flags.fetch("--jobs")) }.freeze #: Hash[String, Setting]

    # The flag of `setting` with what it takes, as `zr help` shows it:
    # `--jobs N`, `--linker auto|ruby|cc`, `--[no-]tune`.
    #: (Setting setting) -> String
    def self.usage(setting)
      values = setting.values
      return setting.flag.sub("--", "--[no-]") if setting.kind == :switch

      "#{setting.flag} #{values.is_a?(Array) ? values.join("|") : values}"
    end

    attr_reader :linker, :host_ruby #: String
    attr_reader :wasm_width #: Integer
    attr_reader :cache #: String?
    attr_reader :cache_max_gb #: Float
    attr_reader :link #: Array[String]

    # The C extensions that a build links in (`ZR_EXT_OBJECTS`): the path
    # of each one's bundle, where ruby would load it from, to the object
    # files that hold its code.
    attr_reader :ext_objects #: Hash[String, Array[String]]

    # The gems whose C extension a build links as the host ruby built it
    # (`ZR_NATIVE_EXT`), by name, each with the version it asks for, nil
    # for the newest installed, or false for `-NAME`: NAME's port.
    attr_reader :native_ext #: Hash[String, String | false | nil]

    # The gems whose C extension zr builds with arguments for its
    # extconf.rb (`ZR_EXT_CONFIG`), by name.
    attr_reader :ext_config #: Hash[String, Array[String]]

    # How a build runs a C extension (`ZR_EXT`): static, embed or dynamic.
    attr_reader :ext_mode #: String

    # The settings from `given` (by variable name, as `CLI.settings!`
    # reads the flags), and the rest from `env`.
    #: (?Hash[String, String] given, ?(Hash[String, String] | RBS::Unnamed::ENVClass) env) -> void
    def initialize(given = {}, env = ENV)
      @given = given
      @env = env
      @linker = choice("ZR_LINKER", LINKERS, "auto")
      @jobs_given = !value("ZR_JOBS").empty?
      @jobs = number("ZR_JOBS", nil, "4", min: 1) if @jobs_given
      # Not exposed as a plain reader: `eval` is a Kernel method, and
      # `eval_walk?` is the only thing anything reads this for.
      @eval_mode = text("ZR_EVAL")
      @timing = switch?("ZR_TIMING")
      @quiet = switch?("ZR_QUIET")
      @verify = switch?("ZR_VERIFY")
      @kernel_checked = switch?("ZR_KERNEL_CHECKED")
      @wasm_names = switch?("ZR_WASM_NAMES")
      # `ZR_WASM_WIDTH`: the group size of a large wasm function's dispatch
      # (`Backend::Wasm::Codegen::Body::LADDER` explains the default).
      @wasm_width = number("ZR_WASM_WIDTH", 256, "256", min: 1)
      @tune = switch?("ZR_TUNE", default: true)
      @cache = text("ZR_CACHE")
      # `ZR_CACHE_MAX_GB`: the most GB an installed zr keeps in its cache
      # (default 5; 0 turns the limit off).
      @cache_max_gb = number("ZR_CACHE_MAX_GB", 5.0, "10", kind: :Float, min: 0)
      # `ZR_HOST_RUBY`: the ruby that zr starts when it needs ruby itself:
      # to resolve gems (lib/zr/gem_set.rb).
      @host_ruby = text("ZR_HOST_RUBY") || running_ruby
      # `ZR_LINK_ARGS`: words for the system linker, as `--link` gives
      # them, split as a shell splits them.
      @link = words(value("ZR_LINK_ARGS")).freeze
      # `ZR_EXT_OBJECTS`: shell words, each `bundle=object,object`.
      @ext_objects = words(value("ZR_EXT_OBJECTS")).to_h { |word| ext_object(word) }.freeze
      @ext_mode = choice("ZR_EXT", EXT_MODES, "static")
      # `ZR_NATIVE_EXT`: gem names, split at commas and spaces, each
      # `name`, `name=version` or `-name`.
      @native_ext = value("ZR_NATIVE_EXT").to_s.split(/[\s,]+/).reject(&:empty?).to_h { |word| native_gem(word) }.freeze
      # `ZR_EXT_CONFIG`: shell words, each `gem=argument`; a gem's
      # arguments in their order.
      @ext_config = words(value("ZR_EXT_CONFIG")).map { |word| ext_argument(word) }
                                                 .group_by(&:first).transform_values { |pairs| pairs.map(&:last) }.freeze
      @run_cache = switch?("ZR_RUN_CACHE", default: true)
      @trace = switch?("ZR_TRACE")
      @code_cache = choice("ZR_CODE_CACHE", CODE_CACHES, "1")
      @fingerprint = SETTINGS.select(&:steers).to_h { |setting| [setting.env, value(setting.env)] }.freeze
      freeze
    end

    # The value of each setting that changes what a build writes
    # (test/support/binaries.rb keys a kept binary on it).
    attr_reader :fingerprint #: Hash[String, String]

    # The value of `name`: its flag's, else its variable's, else "".
    #: (String name) -> String
    def value(name) = @given.fetch(name) { @env[name].to_s }
    private :value

    # What a message calls `name`: its flag when the flag gave the value.
    #: (String name) -> String
    def source(name) = @given.key?(name) ? Config.setting(name).flag : name
    private :source

    # The value of `name`, or nil when it is empty.
    #: (String name) -> String?
    def text(name) = (given = value(name)).empty? ? nil : given
    private :text

    # Whether `name` is on: empty gives `default`, "0" is off, and any
    # other value is on.
    #: (String name, ?default: bool) -> bool
    def switch?(name, default: false) = Config.on?(value(name), default)
    private :switch?

    # The words of `line` as Shellwords.split gives them. The compiler does
    # not require shellwords: the compiler goes into a program with eval,
    # and a require of shellwords there would give the program
    # String#shellsplit, String#shellescape and Array#shelljoin before the
    # program asks for them.
    #: (String line) -> Array[String]
    def words(line)
      words = [] #: Array[String]
      field = +""
      line.scan(/\G\s*(?>([^\0\s\\'"]+)|'([^\0']*)'|"((?:[^\0"\\]|\\[^\0])*)"|(\\[^\0]?)|(\S))(\s|\z)?/m) do |groups|
        # The pattern has groups, so `scan` yields an Array of them.
        word, sq, dq, esc, garbage, sep = groups #: Array[String?]
        raise Invalid, "#{source("ZR_LINK_ARGS")} has a quote with no end: #{line.inspect}. Close the quote, or put a \\ before it." if garbage

        # One of the five groups matches; the last is an escape.
        field << (word || sq || dq&.gsub(/\\([$`"\\\n])/, '\\1') || esc.to_s.gsub(/\\(.)/, '\\1'))
        next unless sep

        words << field
        field = +""
      end
      words
    end
    private :words

    # One word of `ZR_EXT_OBJECTS`: a bundle's path and its objects, with
    # both made absolute; or a bundle's path alone, with no objects, for
    # the bundle itself (`Ext::Source.given`).
    #: (String word) -> [String, Array[String]]
    def ext_object(word)
      bundle, objects = word.split("=", 2)
      if bundle.to_s.empty? || objects&.empty?
        name = source("ZR_EXT_OBJECTS")
        raise Invalid, "#{name} has #{word.inspect}. Give each extension as BUNDLE=OBJECT[,OBJECT...] or a BUNDLE alone, " \
                       "for example #{name}=lib/hello.bundle=hello.o."
      end
      [File.expand_path(bundle.to_s), objects.to_s.split(",").map { |object| File.expand_path(object) }]
    end
    private :ext_object

    # One word of `ZR_EXT_CONFIG`: a gem's name and one argument.
    #: (String word) -> [String, String]
    def ext_argument(word)
      name, argument = word.split("=", 2)
      return [name.to_s, argument.to_s] unless name.to_s.empty? || argument.to_s.empty?

      source = source("ZR_EXT_CONFIG")
      raise Invalid, "#{source} has #{word.inspect}. Give each argument as GEM=ARG, for example #{source}=nokogiri=--use-system-libraries."
    end
    private :ext_argument

    # One word of `ZR_NATIVE_EXT`: a gem's name, and its version, nil, or
    # false for `-name`.
    #: (String word) -> [String, String | false | nil]
    def native_gem(word)
      # `-NAME`: NAME's port, not its gem's own C (lib/zr/ext.rb, `wanted`).
      return [word.delete_prefix("-"), false] if word.match?(/\A-[^=]+\z/)

      name, version = word.split("=", 2)
      if name.to_s.empty? || version&.empty?
        source = source("ZR_NATIVE_EXT")
        raise Invalid, "#{source} has #{word.inspect}. Give each gem as NAME or NAME=VERSION, for example #{source}=msgpack."
      end
      [name.to_s, version]
    end
    private :native_gem

    # The ruby that runs zr, or `ruby` on PATH in a binary that zr built,
    # whose `RbConfig.ruby` names the zr that started it.
    #: () -> String
    def running_ruby = Binary.running? ? "ruby" : RbConfig.ruby
    private :running_ruby

    # The value of `name` when it is one of `values`, or `default` when
    # it is unset or empty.
    #: (String name, Array[String] values, String default) -> String
    def choice(name, values, default)
      given = value(name)
      return default if given.empty?
      return given if values.include?(given)

      *others, last = values
      name = source(name)
      raise Invalid, "#{name} is #{given.inspect}. Set it to #{others.join(", ")} or #{last}, for example #{name}=#{default}."
    end

    # The number in `name` (an Integer, or with `kind: :Float` any
    # number) that is at least `min`, or `default` when it is unset or
    # empty. `example` is a good value for the message.
    #: (String name, Integer default, String example, ?kind: :Integer, ?min: Integer?) -> Integer
    #: (String name, nil default, String example, ?kind: :Integer, ?min: Integer?) -> Integer?
    #: (String name, Float default, String example, ?kind: :Float, ?min: Integer?) -> Float
    def number(name, default, example, kind: :Integer, min: nil)
      given = value(name)
      return default if given.empty?

      number = Kernel.send(kind, given, exception: false)
      return number if number && (min.nil? || number >= min)

      what = kind == :Integer ? "a whole number" : "a number"
      what += " of #{min} or more" if min
      name = source(name)
      raise Invalid, "#{name} is #{given.inspect}. Set it to #{what}, for example #{name}=#{example}."
    end
    private :choice, :number

    # `ZR_EVAL=walk` builds a native program with the tree-walking
    # interpreter as its eval support, instead of the compiler.
    #: () -> bool
    def eval_walk? = @eval_mode == "walk"

    # `ZR_TIMING=1` prints a line to stderr as each build phase starts and ends.
    #: () -> bool
    def timing? = @timing

    # `ZR_QUIET=1` prints no notice that a long build starts or waits, and
    # no progress line (`Notice`). Warnings about the program stay.
    #: () -> bool
    def quiet? = @quiet

    # `ZR_VERIFY=1` checks each IR function's dominance and operand types
    # (`IR::Verify::Strict`) before it is assembled.
    #: () -> bool
    def verify? = @verify

    # `ZR_KERNEL_CHECKED=1` lowers the kernel with a check at each
    # operator whose meaning differs from Ruby's (`Machine::Function#check_wrap`).
    # It is part of the runtime digest.
    #: () -> bool
    def kernel_checked? = @kernel_checked

    # `ZR_WASM_NAMES=1` adds the wasm name section, for a stack trace or
    # a profiler that reads function names.
    #: () -> bool
    def wasm_names? = @wasm_names

    # `ZR_TUNE=0` keeps ruby's limits and leaves YJIT off.
    #: () -> bool
    def tune? = @tune

    # `ZR_TRACE=1` builds the program with its trace events armed, as
    # `--trace` does, for a TracePoint that it reaches by a computed name.
    #: () -> bool
    def trace? = @trace

    # `ZR_RUN_CACHE=0` makes `zr run` build each run (`Cache::Run`).
    #: () -> bool
    def run_cache? = @run_cache

    # `ZR_CODE_CACHE`: "1", "0" or "verify" (`Cache::Code`).
    attr_reader :code_cache #: String

    # Whether `ZR_JOBS` sets the worker count. Then it also overrides the
    # memory limit (`Native::Parallel.afforded`).
    #: () -> bool
    def jobs_given? = @jobs_given

    # `ZR_JOBS`, or the processors up to 6. etc loads at the first call,
    # not with this file: the compiler goes into a program with eval, and
    # etc would give that program IO#pathconf.
    #: () -> Integer
    def jobs
      # `ZR_JOBS` gives a number when it is set.
      given = @jobs #: Integer
      return given if @jobs_given

      require "etc"
      [Etc.nprocessors, 6].min
    end

    # The row of the variable `name`.
    #: (String name) -> Setting
    def self.setting(name) = SETTINGS.find { |setting| setting.env == name } || raise(KeyError, name)

    # Takes the flags of settings off the front of `words`, and returns
    # them by variable name, with the words after them. `--` and the
    # first other word stop it.
    #: (Array[String] words) -> [Hash[String, String], Array[String]]
    def self.flags(words)
      given = {} #: Hash[String, String]
      rest = words.dup
      while (word = rest.first)
        name, value = word.split("=", 2)
        name, value = "-j", word.delete_prefix("-j") if word.match?(/\A-j\d/)
        setting = FLAGS[name.to_s] or break
        rest.shift
        given[setting.env] = flag_value(setting, name.to_s, value, rest)
      end
      [given, rest]
    end

    # The value that the flag `name` of `setting` gives: "1" or "0" for a
    # switch, else the word after `=` or the next word.
    #: (Setting setting, String name, String? value, Array[String] rest) -> String
    def self.flag_value(setting, name, value, rest)
      if setting.kind == :switch
        raise Invalid, "#{name} takes no value. Give #{name} alone." if value

        return name.start_with?("--no-") ? "0" : "1"
      end
      value ||= rest.shift
      raise Invalid, "#{name} needs a value: #{usage(setting)}." if value.nil?

      value
    end
    private_class_method :flag_value

    # The settings that the command line gave, by variable name.
    #: () -> Hash[String, String]
    def self.given = Session.current.memo(:settings) { {} }

    # Uses `given` (from `flags`) for the settings of this process, and
    # reads them again at the next `current`.
    #: (Hash[String, String] given) -> void
    def self.given!(given)
      Session.current.set(:settings, given.freeze)
      reset!
    end

    # `ZR_DEBUG=1` (or `--backtrace`) shows the backtrace of an error that
    # stops zr (`CLI.guard`). It is read on its own, not with the rest: it
    # must work when another setting is bad.
    #: () -> bool
    def self.debug? = on?(given.fetch("ZR_DEBUG") { ENV["ZR_DEBUG"] }, false)

    # Whether `value` is on: nil or empty gives `default`, "0" is off,
    # and any other value is on.
    #: (String? value, bool default) -> bool
    def self.on?(value, default) = value.nil? || value.empty? ? default : value != "0"

    # The one instance for this process. A later call returns the same
    # instance; `reset!`, `given!` and `with` are the only way to get a
    # new one.
    #: () -> Config
    def self.current = Session.current.memo(:config) { new(given) }

    # Drops the current instance, so the next `current` reads `ENV` again.
    #: () -> void
    def self.reset!
      Session.current.forget(:config)
    end

    # Sets each of `ENV` (by keyword, e.g. `ZR_TUNE: "0"`) for the block,
    # yields the `Config` that reading it there gives, and puts `ENV`
    # back after. For tests only; a build reads `Config.current` once.
    #: [T] (**String? overrides) { (Config) -> T } -> T
    def self.with(**overrides)
      saved = overrides.to_h { |name, _| [name, ENV[name.to_s]] }
      begin
        overrides.each { |name, value| ENV[name.to_s] = value }
        reset!
        yield current
      ensure
        saved.each { |name, value| ENV[name.to_s] = value }
        reset!
      end
    end
  end
end
