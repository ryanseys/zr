# frozen_string_literal: true

require "spec_helper"

describe "Kernel: loading files" do
  it "bare require needs a load path root" do
    result = ze0(<<~'RUBY', files: beside("bare_require/lib/thing.rb", "bare_require/vendor/thing/lib/thing.rb"))
      # `require "thing"` names the `thing.rb` sitting under a `$LOAD_PATH` root --
      # not every loaded file whose path happens to end in `/thing.rb`. zeo compared
      # `$LOADED_FEATURES` by path SUFFIX alone, so a vendored copy already loaded
      # under its own long path claimed the bare name, the require answered `false`,
      # and the real file never ran.
      #
      # bundler vendors fileutils at `bundler/vendor/fileutils/lib/fileutils.rb` and
      # loads it by `require_relative`. rubygems' `Gem.open_file_with_lock` then
      # writes `require "fileutils"; FileUtils.rm_f`, and that require answered
      # `false` against the vendored path -- so `FileUtils` was undefined and
      # `bundle install` raised on its last step.

      require_relative "bare_require/vendor/thing/lib/thing"
      p Vendored::THING
      $LOAD_PATH.unshift File.expand_path("bare_require/lib", __dir__)
      p require("thing")
      p Thing::WHICH
      p require("thing")
    RUBY

    _(result).must_answer <<~'OUT'
      :vendored
      true
      :real
      false
    OUT
  end

  it "boot preloaded feature needs no require" do
    result = ze0(<<~'RUBY')
      # `Monitor` needs NO require: ruby 4.0 loads `monitor` before the program's
      # first line, so its constant is there whatever the program says
      # (oracle-verified). The ext gate is about a feature ruby does NOT preload;
      # `Base64` is the shape that test belongs to, and it lives beside the
      # positional-require golden.

      p Monitor.new.class
    RUBY

    _(result).must_answer "Monitor\n"
  end

  it "computed require loads a bundled library" do
    result = ze0(<<~'RUBY')
      # A `require` whose argument is not a literal has to reach the libraries the
      # runtime carries, not just the files on `$LOAD_PATH`.
      #
      # zeo folds a LITERAL `require "date"` at compile time -- the native half is
      # linked in and registered before line 1, so the fold emits nothing but a
      # loaded-feature marker. A computed target names no feature the compiler can
      # see, so it reaches `Kernel#require` at run time instead, and that path used
      # to search only the disk. `$LOAD_PATH` is empty by default and a bundled
      # library is inside the binary rather than on it, so every one of these raised
      # `LoadError`.
      #
      # `%w[...].each { |f| require f }` over stdlib names is the idiom RubyGems,
      # Bundler and Rails all write, so the blast radius was most of the ecosystem.

      names = %w[date set stringio strscan pathname time bigdecimal
                 zlib socket monitor objspace digest etc fcntl]
      names.each { |f| puts "#{f}\t#{require f}" }

      # Ruby's boolean, both halves: true the first time, false for a feature
      # already loaded -- and false even on the FIRST require of one ruby loads
      # before line 1.
      puts "second time"
      names.each { |f| puts "#{f}\t#{require f}" }

      # Every spelling of a non-literal argument reaches the same place.
      one = "json"
      puts "variable\t#{require one}"
      puts "interpolated\t#{require "#{'string'}io"}"
      puts "method result\t#{require ["etc"].first}"

      # A name nothing provides still raises, and the message is ruby's.
      begin
        missing = "no_such_library_anywhere"
        require missing
      rescue LoadError => e
        puts "missing\t#{e.message}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      date	true
      set	false
      stringio	true
      strscan	true
      pathname	true
      time	true
      bigdecimal	true
      zlib	true
      socket	true
      monitor	false
      objspace	true
      digest	true
      etc	true
      fcntl	true
      second time
      date	false
      set	false
      stringio	false
      strscan	false
      pathname	false
      time	false
      bigdecimal	false
      zlib	false
      socket	false
      monitor	false
      objspace	false
      digest	false
      etc	false
      fcntl	false
      variable	true
      interpolated	false
      method result	false
      missing	cannot load such file -- no_such_library_anywhere
    OUT
  end

  it "computed require reveals the gated constant" do
    result = ze0(<<~'RUBY')
      # Loading a feature is only half of a `require`: the constant it gates has to
      # start existing at that line, and not before.
      #
      # zeo registers a require-gated builtin's class only when some file requires
      # its feature, so a program whose only require is COMPUTED registered nothing
      # and the constant stayed a `NameError` even after the load succeeded. The
      # compiler now registers every gated builtin for such a program, CONCEALED --
      # which is the shape an activated one already had -- so the constant is absent
      # until the require reveals it, exactly as in ruby.

      gated = %w[StringIO StringScanner BigDecimal Etc]

      def looked_up(name)
        Object.const_get(name)
        "found"
      rescue NameError
        "absent"
      end

      puts "before"
      gated.each { |n| puts "  #{n}\t#{looked_up(n)}" }

      %w[stringio strscan bigdecimal etc].each { |f| require f }

      puts "after"
      gated.each { |n| puts "  #{n}\t#{Object.const_get(n)}" }

      # And the classes work, not merely resolve.
      puts StringIO.new("hello").read
      puts StringScanner.new("ab12").scan(/[a-z]+/)
      puts BigDecimal("1.25") + BigDecimal("0.25")
      puts Etc.respond_to?(:getpwuid)
    RUBY

    _(result).must_answer <<~'OUT'
      before
        StringIO	absent
        StringScanner	absent
        BigDecimal	absent
        Etc	absent
      after
        StringIO	StringIO
        StringScanner	StringScanner
        BigDecimal	BigDecimal
        Etc	Etc
      hello
      ab
      0.15e1
      true
    OUT
  end

  it "deferred require reopens container" do
    result = ze0(<<~'RUBY', files: beside("deferred_require/lib.rb"))
      # A deferred (in-method) require whose file reopens a compact-path class
      # (`class Outer::Feature::Policy`) BEFORE the forward-declaration it depends on
      # (`module Outer::Feature`) registers -- the rubygems `Gem::Security` shape.
      # The loader hoists the in-method require ahead of this file's own top-level
      # statements, so analyze must resolve the container forward.
      module Outer
      end

      # forward-declaration at load time, like rubygems/security_option.rb
      module Outer::Feature
        class Policy
        end
      end

      def activate
        require_relative "deferred_require/lib"
      end
      activate

      puts Outer::Feature::Policy.new.name
      puts Outer::Feature.digest
    RUBY

    _(result).must_answer "policy\nsha256\n"
  end

  it "loaded features records require" do
    result = ze0(<<~'RUBY')
      require "set"
      p $LOADED_FEATURES.any? { |f| f.include?("set") }
      p $LOADED_FEATURES.empty?
    RUBY

    _(result).must_answer "true\nfalse\n"
  end

  it "missing require names the library" do
    result = ze0(<<~'RUBY')
      require "stringio"

      io = StringIO.new
      io << "ok"
      p io.string

      class Set
        def initialize
          @a = []
        end

        def add(x)
          @a << x
          self
        end

        def size
          @a.size
        end
      end

      s = Set.new
      s.add(1).add(2)
      p s.size
    RUBY

    _(result).must_answer <<~'OUT'
      "ok"
      2
    OUT
  end

  it "native require relative defers to runtime" do
    result = ze0(<<~'RUBY')
      # `require_relative` of a NATIVE (.so/.bundle) feature names a compiled
      # extension zeo cannot load. The call keeps its site and raises the catchable
      # runtime LoadError -- CRuby's own answer when the file is absent -- instead
      # of failing the whole compile. Both the rescued and the bare-but-reached
      # spellings stay programs.
      begin
        require_relative "ext/never_built.so"
      rescue LoadError => e
        p e.class
        p e.message.include?("never_built")
      end

      def optional_native
        require_relative "also_never_built.bundle"
      rescue LoadError
        :fell_back
      end
      p optional_native
      puts "still running"
    RUBY

    _(result).must_answer <<~'OUT'
      LoadError
      true
      :fell_back
      still running
    OUT
  end

  it "optional require relative" do
    result = ze0(<<~'RUBY')
      # A `require_relative` under a `rescue LoadError` is the optional-native-half
      # idiom: rgeo requires its C implementation and catches the LoadError when it
      # is absent. The missing target keeps its CALL and raises at runtime for the
      # rescue to catch, instead of failing the compile.
      begin
        require_relative "no_such_native_half"
      rescue LoadError => e
        puts "fallback: #{e.class}"
      end

      # The protection is the begin BODY only: a bare rescue catches StandardError,
      # which does not cover LoadError, so this shape stays a compile error and is
      # not in this file. A resolvable require_relative under the same rescue still
      # splices; nothing here tests it twice.
      puts "continues"
    RUBY

    _(result).must_answer "fallback: LoadError\ncontinues\n"
  end

  it "plain require resolves against search roots including nested features" do
    files = beside("plain_require/main.rb",
                "plain_require/vendorlib/util/strings.rb",
                "plain_require/vendorlib/util.rb")

    result = ze0(<<~'RUBY', files: files)
      $LOAD_PATH.unshift(File.expand_path("plain_require/vendorlib", __dir__))
      require_relative "plain_require/main"
    RUBY

    _(result).must_answer <<~'OUT'
      util/strings loaded
      util loaded
      util root
      42
    OUT
  end

  it "re require answers false" do
    result = ze0(<<~'RUBY', files: beside("re_require/dep.rb", "re_require/other.rb", "re_require/pair.rb"))
      # `require` answers true the first time and false every time after -- the
      # question is whether the FEATURE loaded, not whether this call site ran.
      #
      # A resolvable literal require folds to a boolean at compile time, and the
      # fold used to answer `true` unconditionally: it sees a NAME, and which file
      # that name resolves to is the loader's knowledge, not the lowering's. So
      # every re-require of a file read as a first load. (A re-require of a BUILTIN
      # was already right -- that arm tracks its own activation set.)
      #
      # The two spellings must agree with each other as well as with themselves:
      # they name one file, so the second one is a re-require whichever came first.

      # Statement position, three times.
      p require_relative("re_require/dep")
      p require_relative("re_require/dep")
      p require_relative("re_require/dep")

      # A second file's require of the same target is a re-require too.
      require_relative "re_require/other"

      # Twice inside ONE statement, on a file nothing has loaded yet: the first
      # loads, the second does not. The statement's own splice has not happened when
      # the fold runs, so both call sites read the loaded set as free.
      p [
        require_relative("re_require/pair"),
        require_relative("re_require/pair"),
      ]

      # A runtime call answers from the loaded set, not from a fold.
      p [1, 2].map { require_relative("re_require/dep") }

      # A builtin feature, whose re-require was already correct.
      p require("set")
      p require("set")

      p DEP
      p PAIR
    RUBY

    _(result).must_answer <<~'OUT'
      dep.rb ran
      true
      false
      false
      false
      pair.rb ran
      [true, false]
      [false, false]
      false
      false
      :dep
      :pair
    OUT
  end

  it "require in a block runs when the block runs" do
    files = beside("require_in_block/in_body.rb",
                "require_in_block/lazy.rb",
                "require_in_block/never.rb",
                "require_in_block/once.rb",
                "require_in_block/repeat.rb")

    result = ze0(<<~'RUBY', files: files)
      # A block body runs only when something yields to it, and how many times is a
      # runtime fact -- so a `require` written inside one is not a load this compile
      # can perform ahead of time. rack's test helper is the shape that found it:
      #
      #   def self.separate_testing   # the non-SEPARATE definition
      #   end
      #   separate_testing do
      #     require_relative "../lib/rack/utils"
      #   end
      #
      # The method does not yield, so CRuby never loads the target. Splicing the
      # require at the enclosing statement's position loaded it anyway, and
      # rack/constants.rb -- already loaded through rack.rb -- ran a second time,
      # warning on all 57 of its constants.
      #
      # Each target below prints when its body runs, so the ORDER and the COUNT are
      # both visible, and every marker is read back through `Object.const_defined?`
      # rather than `defined?` (a constant a gated unit assigns is one zeo answers
      # for at run time, and `defined?` folds).

      def self.never_yields
        :no_yield
      end

      def self.yields_once
        yield
      end

      # 1. The block never runs, so neither does its require.
      never_yields do
        require_relative "require_in_block/never"
      end
      p Object.const_defined?(:NEVER_MARKER)

      # 2. A block that does run loads its target at the point it runs, after the
      #    statement before it.
      puts "before once"
      yields_once do
        require_relative "require_in_block/once"
      end
      puts "after once"
      p Object.const_defined?(:ONCE_MARKER)

      # 3. A lambda body is a block too: nothing loads until it is called.
      loader = -> { require_relative "require_in_block/lazy" }
      p Object.const_defined?(:LAZY_MARKER)
      loader.call
      p Object.const_defined?(:LAZY_MARKER)

      # 4. A block that runs many times loads its target once, and `require_relative`
      #    answers false from the second run on.
      answers = [1, 2, 3].map do
        require_relative "require_in_block/repeat"
      end
      p answers

      # 5. A block inside a class body is the same case -- `class_eval` does yield,
      #    so this one loads.
      class Host
        [:only].each do
          require_relative "require_in_block/in_body"
        end
      end
      p Holder::IN_BODY_MARKER

      # 6. The rack shape end to end: a require reached only through a block that
      #    never yields leaves the file unloaded, and a later require of it from a
      #    position that DOES run loads it exactly once.
      never_yields do
        require_relative "require_in_block/never"
      end
      p require_relative("require_in_block/never")
      p NEVER_MARKER
      p require_relative("require_in_block/never")
    RUBY

    _(result).must_answer <<~'OUT'
      false
      before once
      once.rb ran
      after once
      true
      false
      lazy.rb ran
      true
      repeat.rb ran
      [true, false, false]
      in_body.rb ran
      :in_body
      never.rb ran
      true
      :never
      false
    OUT
  end

  it "require in a block that never yields does not load" do
    result = ze0(<<~'RUBY', files: beside("require_in_unyielded_block/dep.rb", "require_in_unyielded_block/prog.rb"))
      # A block body runs only when something yields to it, so a `require` written
      # inside one is not a load this compile can perform ahead of time. rack's
      # test helper is the shape: `separate_testing do require_relative "..." end`,
      # where the non-SEPARATE definition of that method does not yield.

      require_relative "require_in_unyielded_block/prog"
    RUBY

    _(result).must_answer <<~'OUT'
      false
      dep ran
      [true, false]
      :dep
    OUT
  end

  it "require of a file the eval road holds loads it in sight" do
    result = ze0(<<~'RUBY')
      # A program that evals carries the compiler, whose road loads ffi for
      # its own use, out of sight. The program's own require of ffi brings it
      # into sight: the files it loaded in turn and the constants they define
      # are the program's, as ruby's one require loads them all.
      eval "1"
      p require("ffi")
      p defined?(FFI), defined?(FFI::Pointer), FFI::Pointer.new(0).null?
      p $LOADED_FEATURES.count { |f| f.include?("/ffi/") } > 20
      p require("ffi")

    RUBY

    _(result).must_answer <<~'OUT'
      true
      "constant"
      "constant"
      true
      true
      false
    OUT
  end

  it "require of a preloaded feature answers false" do
    result = ze0(<<~'RUBY')
      # ruby loads these features before the program starts, so a require of
      # one answers false, by any of its names. Only pathname's C half is
      # loaded; a require of pathname still runs its Ruby half.
      p [require("thread"), require("enumerator"), require("rational"), require("complex"), require("fiber")]
      p [require("ruby2_keywords"), require("set"), require("monitor"), require("thread.rb"), require("enumerator.so")]
      p require("pathname")
    RUBY

    _(result).must_answer <<~'OUT'
      [false, false, false, false, false]
      [false, false, false, false, false]
      true
    OUT
  end

  it "require parent" do
    result = ze0(<<~'RUBY', files: beside("require_parent/views/articles/index.rb", "require_parent/views.rb"))
      # Regression: `require_relative ".."` must load the parent directory's
      # `<dir>.rb`. Ruby normalizes "views/articles/.." -> "views" and appends
      # ".rb" -> "views.rb"; Spinel must not glue ".rb" onto a literal ".." to
      # form a bogus "...rb". (Mirrors roundhouse's emitted views, where each
      # view does `require_relative ".."` to pull in the views aggregator.)
      require_relative "require_parent/views/articles/index"
    RUBY

    _(result).must_answer "views aggregator loaded\nindex loaded\n"
  end

  it "required feature inside eval installs its visibility" do
    result = ze0(<<~'RUBY')
      # `require "fileutils"` from inside an `eval` raises where the same require at
      # the top level succeeds:
      #
      #   private method 'public' called for class #<Class:FileUtils::Verbose>
      #
      # The file is CRuby's own `fileutils.rb`, unmodified, and the construct is at
      # its line 2650:
      #
      #   module Verbose
      #     include FileUtils
      #     names = ::FileUtils.collect_method(:verbose)
      #     names.each { |name| module_eval("def #{name}(*args, **options) ... end") }
      #     private(*names)
      #     extend self
      #     class << self
      #       public(*::FileUtils::METHODS)
      #     end
      #   end
      #
      # Two facts locate it. The same `require` compiled STATICALLY works, in both
      # the JIT and an AOT binary -- so the unit itself lowers correctly. And the
      # construct alone, written out by hand inside an `eval`, also works: a module
      # with a private instance method, `extend self`, and `class << self;
      # public(:a); end` answers correctly. What fails is the two together, so the
      # trigger is something the smaller shape does not carry -- `include` of a
      # large module, or the `module_eval`-defined names, in a unit the RUN TIME
      # compiled rather than the compile did.
      #
      # This is the recurring shape zeo's notes keep finding, one layer further in:
      # a visibility verb the run time owns, applied against a set the compile-time
      # view of the unit assembled. `private_constant` and `K.prepend` were the same
      # bug at the top level and are fixed; this is the eval seam's copy of it.
      #
      # It BLOCKS DOGFOODING. A ruby tool compiled to a binary with `zeo -o`
      # but its entry point unshifts a computed path onto `$LOAD_PATH`, so zeo
      # cannot resolve those requires statically and defers each one to a run-time
      # compile. The first library that requires `fileutils` then dies at load, and
      # no zeo-compiled tool starts.

      eval(%q{require "fileutils"})
      puts FileUtils::Verbose.name
      puts FileUtils::Verbose.singleton_class.public_method_defined?(:cp)
    RUBY

    _(result).must_answer "FileUtils::Verbose\ntrue\n"
  end

  it "resolve feature path answers where a require would land" do
    result = ze0(<<~'RUBY')
      require "tmpdir"

      p $LOAD_PATH.respond_to?(:resolve_feature_path)
      # Ruby puts it on THIS array, not on Array -- a plain array must not answer.
      p [].respond_to?(:resolve_feature_path)
      p $LOAD_PATH.singleton_methods.sort

      # A real file on a load-path root: the kind is :rb and the path is absolute.
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "zeo_probe_feature.rb"), "ZEO_PROBE_FEATURE = 1\n")
        $LOAD_PATH.unshift(dir)
        r = $LOAD_PATH.resolve_feature_path("zeo_probe_feature")
        # Absolute and REAL: the tmpdir is a symlink on macOS, so the answer is the
        # resolved path rather than the one that was unshifted.
        p [r[0], File.basename(r[1]), r[1].start_with?("/"), r[1] == File.realpath(File.join(dir, "zeo_probe_feature.rb"))]
        # The explicit `.rb` spelling names the same file.
        r = $LOAD_PATH.resolve_feature_path("zeo_probe_feature.rb")
        p [r[0], File.basename(r[1])]
        $LOAD_PATH.delete(dir)
      end

      # Nothing supplies it: nil, not a raise.
      p $LOAD_PATH.resolve_feature_path("no_such_lib_xyz")

      # Ruby folded these into core and keeps the name only so old code loads. It
      # has no file for them anywhere, so the answer is nil.
      %w[set fiber thread rational complex].each do |f|
        p [f, $LOAD_PATH.resolve_feature_path(f)]
      end

      # Anything but a String is a TypeError, and nil is NOT the no-argument case.
      [nil, 42, :json].each do |bad|
        begin
          $LOAD_PATH.resolve_feature_path(bad)
          p :no_raise
        rescue TypeError => e
          p e.class
        end
      end
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      [:resolve_feature_path]
      [:rb, "zeo_probe_feature.rb", true, true]
      [:rb, "zeo_probe_feature.rb"]
      nil
      ["set", nil]
      ["fiber", nil]
      ["thread", nil]
      ["rational", nil]
      ["complex", nil]
      TypeError
      TypeError
      TypeError
    OUT
  end

  it "run time compile reruns a loaded feature" do
    result = ze0(<<~'RUBY', files: fixtures("reloaded_feature/wants_forwardable.rb"))
      require "forwardable"
      $LOAD_PATH.unshift(File.expand_path("../../fixtures/reloaded_feature", __dir__))
      name = "wants_forwardable"
      require name
      p WantsForwardable.ok
    RUBY

    _(result).must_answer "true\n"
  end

  it "runtime required gems dependency loads" do
    result = ze0(<<~'RUBY')
      # A `require` reached only from a METHOD BODY loads the vendored gem at
      # run time -- but the gem's own nested dependency require does not
      # deliver its constants: tempfile's `require "tmpdir"` leaves
      # Dir::Tmpname undefined and Tempfile.create raises NameError. The
      # top-level-require form works. A cousin of the dual-homed fold in
      # `error_highlight_library.rb`. (Found by the 2026-08-24 probe sweep.)
      def go
        require "tempfile"
        Tempfile.create("x") { puts "created" }
      end
      go
    RUBY

    _(result).must_answer "created\n"
  end

  it "second require of one feature answers false" do
    result = ze0(<<~'RUBY')
      p require("json")
      p require("json")

      # Already loaded before line 1, so even the FIRST require answers false.
      p require("set")
      p require("set")

      # Two requires inside one statement: the first loads, the second does not.
      p [require("digest"), require("digest")]

      # A gem with a Ruby half on disk answers the same way, and the require makes
      # its constant resolvable at the same time.
      loaded = require("csv")
      p [loaded, defined?(CSV)]
      p require("csv")
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      false
      false
      [true, false]
      [true, "constant"]
      false
    OUT
  end

  it "splat require defers to runtime" do
    result = ze0(<<~'RUBY')
      # `require(*names)` has no compile-time feature name -- the call stays live
      # and the runtime `Kernel#require` raises the catchable `LoadError`, which
      # is the whole point: every corpus hit sits inside a `rescue LoadError`
      # optional-dependency helper (wagons, right_support).
      #
      # zeo's require recognizer checked the argument COUNT (one) before the
      # shape, so a single splat slipped past it into the generic lowering and
      # died on "unsupported syntax at \"*names\"".
      def try_require(*names)
        require(*names)
        "loaded"
      rescue LoadError
        "unavailable"
      end

      puts try_require("zeo_definitely_does_not_ship_this")
    RUBY

    _(result).must_answer "unavailable\n"
  end
end
