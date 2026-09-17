# frozen_string_literal: true

require "spec_helper"

describe "Units programs" do
  it "autoload and a guarded require of one file share its unit" do
    result = ze0(<<~'RUBY', files: {"an_autoload_and_a_guarded_require_of_one_file_share_its_unit/lib/pkg/target.rb" => "puts \"target ran\"\nmodule Pkg\n  class Target\n    SPLIT = :split\nclass << self\n  def read = SPLIT\nend\n  end\nend\n", "an_autoload_and_a_guarded_require_of_one_file_share_its_unit/lib/pkg.rb" => "puts \"pkg ran\"\nmodule Pkg\n  autoload :Target, \"pkg/target\"\nend\n", "an_autoload_and_a_guarded_require_of_one_file_share_its_unit/prog.rb" => "def self.never_yields\n  :no_yield\nend\nrequire_relative \"lib/pkg\" if ENV[\"HOME\"]\nnever_yields do\n  require_relative \"lib/pkg/target\"\nend\nputs \"before read\"\np Pkg::Target.read\n"})
      # One file demanded twice under two different names: an `autoload` naming it
      # on the load path, and a guarded `require_relative` naming it by path. rack
      # writes both, and the second never runs.
      #
      # The two demands reach the loader in DIFFERENT rounds of its unit sweep --
      # the `require_relative` while `prog.rb` lowers, the `autoload` only once
      # `pkg.rb` is itself spliced as a unit -- so a unit registered under
      # whichever name arrived first dropped the other. When the one dropped was
      # the autoload's, the read that should have run the unit found no unit under
      # that name and did nothing: `Pkg::Target` still resolved (a unit's classes
      # are in the dispatch tables from startup) and `Pkg::Target.read` was still
      # callable, so the only symptom was its body's constant missing.

      $LOAD_PATH.unshift(File.expand_path("an_autoload_and_a_guarded_require_of_one_file_share_its_unit/lib", __dir__))
      require_relative "an_autoload_and_a_guarded_require_of_one_file_share_its_unit/prog"
    RUBY

    _(result).must_answer <<~'OUT'
      pkg ran
      before read
      target ran
      :split
    OUT
  end

  it "autoload target compiled as a unit" do
    result = ze0(<<~'RUBY', files: {"an_autoload_target_compiled_as_a_unit/cmd.rb" => "require File.expand_path(\"thing\", __dir__)\n", "an_autoload_target_compiled_as_a_unit/demo.rb" => "module Demo\n  autoload :Thing, File.expand_path(\"thing\", __dir__)\nend\n", "an_autoload_target_compiled_as_a_unit/spec.rb" => "module Demo\n  class Spec\n    def self.value = Thing::VALUE\n  end\n  # A METHOD-BODY require is lazy, so `cmd.rb` becomes a unit -- and\n  # `thing.rb` is pulled into that unit rather than into the program.\n  def self.late\n    require_relative \"cmd\"\n  end\nend\n", "an_autoload_target_compiled_as_a_unit/thing.rb" => "module Demo\n  class Thing\n    VALUE = 42\n  end\nend\n"})
      # An `autoload` declared inside a file that is itself compiled as a LOAD-PATH
      # UNIT runs its target when the constant is READ, whichever spelling named it,
      # and whether or not anything else ever requires it.
      #
      # A `$LOAD_PATH.unshift` of a computed directory makes zeo compile that whole
      # directory as units, each with its own compiler and its own `autoload_consts`
      # name set -- so the `autoload` here is seen only by demo.rb's compile while
      # the read is emitted by the main program's, whose set is empty. What closes
      # the gap is not sharing that set but widening the RESOLUTION: an `autoload`
      # is a deferred `require`, so `run_pending_autoload` walks the same chain
      # `Kernel#require` walks -- the compiled-in unit table, then the load path.
      # Answering out of the unit table alone left a target the emitting compile
      # never saw silently unloaded.

      $LOAD_PATH.unshift(File.join(__dir__, "an_autoload_target_compiled_as_a_unit"))
      require "demo"
      require "spec"
      p Demo::Thing::VALUE
      p Demo::Spec.value
      p Demo.autoload?(:Thing).nil?
    RUBY

    _(result).must_answer <<~'OUT'
      42
      42
      true
    OUT
  end

  it "autoload target is a unit only target" do
    result = ze0(<<~'RUBY', files: {"an_autoload_target_is_a_unit_only_target/cmd.rb" => "require File.expand_path(\"rule\", __dir__)\n", "an_autoload_target_is_a_unit_only_target/lib.rb" => "module Store\n  autoload :Rule, File.expand_path(\"rule\", __dir__)\nend\n", "an_autoload_target_is_a_unit_only_target/rule.rb" => "module Store\n  class Rule\n    LIMIT = 42\n    def self.limit = LIMIT\n  end\nend\n", "an_autoload_target_is_a_unit_only_target/spec.rb" => "module Store\n  class Spec\n    def self.limit = Rule::LIMIT\n  end\n  # A method-body `require_relative` is LAZY, so zeo splices it at the file\n  # tail -- and the file it reaches requires `rule.rb` at top level. That\n  # trailing splice used to claim the autoload's slot.\n  def self.late\n    require_relative \"cmd\"\n  end\nend\n"})
      # An `autoload` target is a UNIT-ONLY target: every other require site that
      # names the same file keeps its call and loads the unit, so whichever runs
      # first runs the body once.
      #
      # Before that rule, a plain splice elsewhere claimed the dedup slot, no unit
      # was built, and the constant read that should have run the target found
      # nothing to run. `require "rubygems"` died on `Gem::Requirement` for exactly
      # this reason: specification.rb reaches requirement.rb through a method-body
      # `require_relative` that zeo splices at the file tail, BELOW the class body
      # that reads the constant.
      #
      # The read also has to ASK. A compiled-in unit's classes are in the dispatch
      # tables from program start, so the read never misses and no `const_missing`
      # hook can carry the load -- the emitter gates the read itself.
      require_relative "an_autoload_target_is_a_unit_only_target/lib"
      require_relative "an_autoload_target_is_a_unit_only_target/spec"

      # Reading the constant is what runs the target.
      p Store::Rule::LIMIT
      p Store::Rule.limit
      p Store::Spec.limit
      # ... and once it has run, ruby reports no pending autoload.
      p Store.autoload?(:Rule).nil?
      # The other site still works, and runs nothing a second time.
      p Store.late
    RUBY

    _(result).must_answer <<~'OUT'
      42
      42
      42
      true
      true
    OUT
  end

  it "autoloaded units body runs" do
    result = ze0(<<~'RUBY', files: {"an_autoloaded_units_body_runs/leaf.rb" => "LEAF_RAN = true\nclass Array\n  def leaf_method = :leaf_method\nend\n", "an_autoloaded_units_body_runs/target.rb" => "require_relative \"leaf\"\nmodule Holder\n  module Target\n    def self.go = :go\n  end\nend\n"})
      # A unit reached through `autoload` runs its BODY, so every constant it
      # assigns is defined from there on.
      #
      # rack is the case that found it: `rack.rb` declares
      # `autoload :Utils, "rack/utils"`, and `rack/utils.rb` opens with
      # `require "time"`. Both files appeared in `$LOADED_FEATURES` -- so the
      # loader thought it had run them -- and yet `Time::VERSION`, assigned on the
      # second line of `class Time`, raised `NameError`. The fixture here is that
      # shape with nothing vendored: the autoload target requires a LEAF, and the
      # leaf's constants are what never appeared.
      #
      # Registration was not execution, and the two were being read as one. A
      # unit's classes register for dispatch at startup -- the static MRO needs a
      # shape -- which made the constant answer before the file ran. Now a unit's
      # class starts CONCEALED and its own body site reveals it, the same
      # mechanism a runtime-conditional class uses; and `Hir::unrun_unit_consts`
      # records every unit's VALUE constants, not just an autoload target's, so a
      # bare-name `defined?` asks the run time rather than folding "written only
      # later" -- a unit is in no statement stream, so later and never-run looked
      # the same.
      #
      # See `a_deferred_require_loads_when_it_runs.rb` for the other half of the
      # same cause.

      module Holder
        autoload :Target, "#{__dir__}/an_autoloaded_units_body_runs/target"
      end

      p defined?(LEAF_RAN)
      p Holder::Target.go
      p defined?(LEAF_RAN)
      p [].leaf_method
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      :go
      "constant"
      :leaf_method
    OUT
  end

  it "conditional require units" do
    result = ze0(<<~'RUBY', files: {"conditional_require_units/loud.rb" => "puts \"loud side effect\"\n", "conditional_require_units/second.rb" => "puts \"second loaded\"\n"})
      # A require under a runtime-undecidable guard runs only when the guard
      # passes -- CRuby's order of events. The false direction: this env var is
      # never set, so `loud.rb`'s side effect must not appear (an eager splice ran
      # it in every compile -- the divergence minitest's hell.rb recorded). The
      # true direction: HOME is set in any test environment, so `second.rb` loads
      # at runtime through its compiled-in unit.
      require_relative "conditional_require_units/loud" if ENV["ZEO_TEST_NEVER_SET"]
      puts "between"
      require_relative "conditional_require_units/second" if ENV["HOME"]
      puts "after"
    RUBY

    _(result).must_answer <<~'OUT'
      between
      second loaded
      after
    OUT
  end

  it "def after an undef in a unit" do
    result = ze0(<<~'RUBY', files: {"a_def_after_an_undef_in_a_unit/tracer.rb" => "class ::Module\n  undef method_added\n  def method_added(mid); end\nend\n"})
      require_relative "a_def_after_an_undef_in_a_unit/tracer"
      p Module.private_method_defined?(:method_added)
      p Module.private_instance_methods(false).sort.grep(/method_/)
      p Module.new.send(:method_added, :anything)
    RUBY

    _(result).must_answer <<~'OUT'
      false
      [:method_removed, :method_undefined]
      nil
    OUT
  end

  it "glob require units" do
    result = ze0(<<~'RUBY', files: {"glob_require_units/loader.rb" => "# The loader sits INSIDE the tree it globs, exactly as tzinfo's ts_all.rb\n# does -- so the demanded unit walk is bounded to this directory.\nDir[File.join(__dir__, \"part_*.rb\")].sort.each { |t| require t }\n", "glob_require_units/part_a.rb" => "PART_A = \"alpha\"\n", "glob_require_units/part_b.rb" => "PART_B = \"beta\"\n"})
      # A glob-driven require loop -- how a test suite (tzinfo's ts_all.rb) or a
      # plugin registry loads itself. The target strings exist only at runtime, so
      # the demanding file's directory is compiled in as callable units and the
      # runtime require resolves what the program builds.
      require_relative "glob_require_units/loader"
      puts PART_A
      puts PART_B
    RUBY

    _(result).must_answer <<~'OUT'
      alpha
      beta
    OUT
  end

  it "guarded def in an earlier unit does not take a later units position" do
    result = ze0(<<~'RUBY', files: {"a_guarded_def_in_an_earlier_unit_does_not_take_a_later_units_position/guarded.rb" => "class C\n  [:tag].each { |n| attr_accessor(n) }\n  if Probe.cpu == \"universal\"\n    ONLY = \"universal\"\n    def which = ONLY\n    def self.which = ONLY\n  end\nend\nrequire \"real\"\n", "a_guarded_def_in_an_earlier_unit_does_not_take_a_later_units_position/main.rb" => "module Probe\n  def self.cpu = [\"arm\", \"64\"].join\nend\nrequire \"guarded\"\nputs C.new.which\nputs C.which\nc = C.new\nc.tag = \"tagged\"\nputs c.tag\n", "a_guarded_def_in_an_earlier_unit_does_not_take_a_later_units_position/real.rb" => "class C\n  def which = \"real\"\n  def self.which = \"real class method\"\nend\n"})
      # The failing shape ACROSS FILES, which is how bundler and rubygems meet:
      # the guarded reopen is a unit walked before the unit holding the real
      # bodies.

      $LOAD_PATH.unshift(File.expand_path("a_guarded_def_in_an_earlier_unit_does_not_take_a_later_units_position", __dir__))
      require_relative "a_guarded_def_in_an_earlier_unit_does_not_take_a_later_units_position/main"
    RUBY

    _(result).must_answer <<~'OUT'
      real
      real class method
      tagged
    OUT
  end

  it "lazy units" do
    result = ze0(<<~'RUBY', files: {"lazy_units/counted.rb" => "# frozen_string_literal: true\n\nCOUNTED_RUNS = (defined?(COUNTED_RUNS) ? COUNTED_RUNS : 0) + 1\nputs \"counted ran\"\n\nmodule Counted\n  def self.mark = :counted\nend\n", "lazy_units/guarded.rb" => "# frozen_string_literal: true\n\nputs \"guarded ran\"\nGUARDED_MARK = :guarded\n", "lazy_units/nested.rb" => "# frozen_string_literal: true\n\nrequire_relative \"counted\"\nputs \"nested ran\"\nNESTED_MARK = Counted.mark\n", "lazy_units/reloaded.rb" => "# frozen_string_literal: true\n\n$reloaded_runs = ($reloaded_runs || 0) + 1\nputs \"reloaded ran\"\n"})
      # frozen_string_literal: true

      # A `require` the compile-time splice cannot reach -- one an `if`
      # guards, one inside a method or a block, one whose name only the run
      # time builds -- keeps its call. The file it names is compiled as a
      # UNIT, and the run-time require runs it at the position the call
      # stands, which is ruby's own order: whether the call runs at all is a
      # run-time fact.

      puts "start"

      # Inside a method: the file runs the first time the method is called,
      # and a second call answers false without running it again.
      def pull(name) = require_relative("lazy_units/#{name}")

      p pull("counted")
      p pull("counted")
      p Counted.mark, COUNTED_RUNS

      # Guarded: the require runs only when the guard lets it.
      require_relative "lazy_units/guarded" if [].empty?
      p GUARDED_MARK

      # Never reached, so the file never runs.
      require_relative "lazy_units/missing_is_never_asked_for" if [1].empty?

      # A name the run time builds. The unit is found by the path it expands
      # to, so a computed spelling reaches the same file.
      %w[counted].each { |name| require_relative "lazy_units/#{name}" }
      p COUNTED_RUNS

      # A unit's own top-level `require_relative` splices into it, so what it
      # needs is there when it runs.
      p pull("nested")
      p NESTED_MARK

      # A computed plain `require` may name any gated builtin.
      feature = "json"
      require feature
      p JSON.parse('{"a":[1,2]}')

      # `load` runs the file again every time and answers true each time; it
      # consults no loaded-feature table, so a unit -- which runs once --
      # can never answer one, and the file is read where it stands.
      here = File.expand_path("lazy_units", __dir__)
      p load("#{here}/reloaded.rb")
      p load("#{here}/reloaded.rb")
      p $reloaded_runs

      puts "end"
    RUBY

    _(result).must_answer <<~'OUT'
      start
      counted ran
      true
      false
      :counted
      1
      guarded ran
      :guarded
      1
      nested ran
      true
      :counted
      {"a" => [1, 2]}
      reloaded ran
      true
      reloaded ran
      true
      2
      end
    OUT
  end

  it "method body require relative loads a unit" do
    result = ze0(<<~'RUBY', files: {"a_method_body_require_relative_loads_a_unit/part.rb" => "PART = \"loaded\"\n"})
      # A `require_relative` written in a METHOD body loads its target when the
      # method RUNS, even when some other site has already made that file a unit.
      #
      # The guard below makes `part.rb` a unit-only target: it is never spliced, and
      # every site naming it keeps its call so that whichever one runs first loads
      # the body once. The method-body site is the only one that ever runs here.
      #
      # It used to load nothing. `RequireCollector` files a method-body
      # `require_relative` under `lazy`, never `calls`, so the statement pre-pass --
      # the one place that consults `unit_only_targets` before lowering -- never saw
      # it. `lower_node` reached the `def` first and folded the call to `true`, and
      # the trailing pass that would have claimed the site ran long after. The call
      # was dead and the file never loaded.
      #
      # Both sites now claim through one helper, `Loader::claim_unit_only_site`. The
      # two arrive at different times, which is the whole bug: a statement-position
      # require claims itself as it lowers, and a method-body one has to claim
      # itself in the pre-pass, ahead of the fold.

      require_relative "a_method_body_require_relative_loads_a_unit/part" if ENV["NEVER"]

      def load_part
        require_relative "a_method_body_require_relative_loads_a_unit/part"
      end

      p defined?(PART)
      p load_part
      p defined?(PART)
      p PART
      # A second call answers false: the feature is loaded.
      p load_part
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      true
      "constant"
      "loaded"
      false
    OUT
  end

  it "process clock gettime unit" do
    result = ze0(<<~'RUBY')
      # clock_gettime honors the clock id and unit. Values are machine time, so
      # assert structure/type (platform-neutral), not exact numbers.
      p(Process.clock_gettime(Process::CLOCK_REALTIME) > 1_000_000_000)
      p(Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond).class)
      p(Process.clock_gettime(Process::CLOCK_MONOTONIC, :second).class)
      p(Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_second).class)
      p(Process::CLOCK_MONOTONIC.is_a?(Integer))
    RUBY

    _(result).must_answer <<~'OUT'
      true
      Integer
      Integer
      Float
      true
    OUT
  end

  it "process clock unit validation" do
    result = ze0(<<~'RUBY')
      # Process.clock_gettime validates its unit (#2727): an unknown literal symbol
      # is CRuby's ArgumentError, not a silent float_second.
      r = (Process.clock_gettime(Process::CLOCK_MONOTONIC, :bogus) rescue $!.class)
      p(r.is_a?(Float) ? :returned_float_no_raise : r)
      p Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond).is_a?(Integer)
      p Process.clock_gettime(Process::CLOCK_MONOTONIC).is_a?(Float)
    RUBY

    _(result).must_answer <<~'OUT'
      ArgumentError
      true
      true
    OUT
  end

  it "runtime unit may yield from a singleton body" do
    _(ze0(<<~'RUBY')).must_answer "20\n"
      DIR = File.expand_path("../../fixtures/singleton_yield", __dir__)
      $LOAD_PATH.unshift(DIR)

      name = "singleton_yield_target"
      require name

      p SingletonYield.take(2) { |v| v * 10 }
    RUBY
  end

  it "time at unit form" do
    result = ze0(<<~'RUBY')
      # Time.at(sec, num, :unit) scales the second argument by the named unit
      # (#2714). CRuby's unit set has no plurals; an unknown one is ArgumentError.
      p Time.at(0, 500, :millisecond).to_f
      p Time.at(0, 500, :usec).to_f
      p Time.at(0, 500, :microsecond).to_f
      p Time.at(0, 500, :nanosecond).to_f
      p Time.at(0, 500, :nsec).to_f
      p Time.at(0, 1.5, :millisecond).to_f
      p Time.at(1, 250, :millisecond).to_f
      r = (begin; Time.at(1, 250, :milliseconds); rescue ArgumentError => e; e.message; end)
      p r
    RUBY

    _(result).must_answer <<~'OUT'
      0.5
      0.0005
      0.0005
      5.0e-07
      5.0e-07
      0.0015
      1.25
      "unexpected unit: milliseconds"
    OUT
  end

  it "time at units matchdata slice and float exponent" do
    result = ze0(<<~'RUBY')
      # MatchData indexes like an array `[full, g1, g2, g3]`, so `md[1, 2]`
      # is `[g1, g2]` and `md[1..]` is `[g1, g2, g3]` (verified against
      # ruby 4.0.6 -- the previous expectation dropped the first capture).

      p Time.at(0, 500, :millisecond).to_f
      p Time.at(0, 500, :nanosecond).to_f
      md = "2024-01-31".match(/(\d+)-(\d+)-(\d+)/)
      p md[1, 2]
      p md[1..]
      p(md == "2024-01-31".match(/(\d+)-(\d+)-(\d+)/))
      p 5.0e-7
      p 1.0e20
    RUBY

    _(result).must_answer <<~'OUT'
      0.5
      5.0e-07
      ["2024", "01"]
      ["2024", "01", "31"]
      true
      5.0e-07
      1.0e+20
    OUT
  end

  it "unit class new dispatches runtime" do
    result = ze0(<<~'RUBY', files: {"unit_class_new_dispatches_runtime/foo/thing.rb" => "module Outer\n  module Foo\n    class Thing\n      def initialize(a, b = 10)\n        @val = a * b\n      end\n      attr_reader :val\n    end\n  end\nend\n"})
      # `.new` on a class whose `initialize` lives in a lazily-loaded unit is a
      # call site like any other: the name de-optimizes to the dynamic path,
      # which resolves the REAL initialize (the static resolution fell through to
      # BasicObject's zero-arity one and baked an arity error -- prism's
      # ParseResult inside rspec-support was the case).
      module Outer
        module Foo
          def self.install(lib, &require_relative)
            name = "helper_#{lib}"
            (class << self; self; end).__send__(:define_method, name) do |f|
              require_relative.call("unit_class_new_dispatches_runtime/#{lib}/#{f}")
            end
          end
          install(:foo) { |f| require_relative(f) }
          helper_foo "thing"
        end
      end
      t = Outer::Foo::Thing.new(5)
      p t.val
      p Outer::Foo::Thing.new(7, 2).val
    RUBY

    _(result).must_answer <<~'OUT'
      50
      14
    OUT
  end

  it "unit records its own path in loaded features" do
    result = ze0(<<~'RUBY', files: {"a_unit_records_its_own_path_in_loaded_features/part.rb" => "PART_OK = true\n"})
      # `$LOADED_FEATURES` names the FILE a require loaded, never the spelling the
      # require asked under. CRuby lists absolute paths, and real libraries read that
      # list: rubygems' `already_loaded?` compares `"#{load_path_entry}/#{file}"`
      # against it, and bundler's `shared_helpers` asks each entry
      # `start_with?(resolved_path)`.
      #
      # A compiled-in unit used to append the require's own spelling instead, so a
      # short name landed where a path belonged and both those checks answered wrong.
      # Each unit row now carries its own source file, and that is what the load
      # records.

      require_relative "a_unit_records_its_own_path_in_loaded_features/part" if ENV["NEVER"]

      def load_part
        require_relative "a_unit_records_its_own_path_in_loaded_features/part"
      end

      load_part
      entry = $LOADED_FEATURES.last
      p entry.start_with?("/")
      p File.basename(entry)
      p File.exist?(entry)
      # One entry per FILE, however many spellings reach it.
      p $LOADED_FEATURES.count { |f| File.basename(f) == "part.rb" }
    RUBY

    _(result).must_answer <<~'OUT'
      true
      "part.rb"
      true
      1
    OUT
  end

  it "unit reopen of kernel is positional" do
    result = ze0(<<~'RUBY', files: {"a_unit_reopen_of_kernel_is_positional/patch.rb" => "module Kernel\n  MONITOR = \"monitor\"\n  alias_method :orig_require, :require\n  def require(path)\n    MONITOR\n    orig_require(path)\n  end\nend\n", "a_unit_reopen_of_kernel_is_positional/pkg.rb" => "# A computed require makes this package's whole load path compile as\n# UNITS, which is what puts patch.rb in a unit rather than a splice.\nrequire ENV[\"ZEO_NEVER_SET\"] if ENV[\"ZEO_NEVER_SET\"]\nputs \"before\\t\#{require(\"set\")}\"\neval File.read(File.join(__dir__, \"patch.rb\")), nil, \"patch.rb\"\nputs \"after\\t\#{require(\"tmpdir\")}\"\n"})
      # A reopen of a builtin inside a LAZY UNIT is positional too.
      #
      # A reopen normally gets one `.bss` byte -- `zeo_reopen_flags` -- stored at
      # the `class Foo ... end` and read by the reopened body, which forwards to
      # the row it replaced while the byte is zero. A unit's file was EXCLUDED
      # from that, because a unit that is never required leaves the byte at zero
      # for the whole program, and a name the unit ADDS would then answer
      # `undefined method` forever.
      #
      # The cost of the exclusion was the whole reason `require "rubygems"` did
      # not work. RubyGems reaches `kernel_require.rb` through `eval
      # File.read(path)`, and zeo also compiles that file as a unit because the
      # package computes a require. Its `def require` therefore registered at
      # BOOT -- before the `module Kernel` body that declares the constant that
      # body reads -- so the first require in rubygems.rb raised `uninitialized
      # constant RUBYGEMS_ACTIVATION_MONITOR`.
      #
      # A unit's flag now reads the other way: at zero, forward to the native row
      # IF THERE IS ONE (`zeo_rt_native_row_exists`), and otherwise run the body.
      # A name the unit adds keeps answering; a name it REPLACES answers natively
      # until the unit runs, which is ruby's own order.
      #
      # Two more things had to move with it. Object's method table holds what a
      # module MATERIALIZED onto it, so a `def require` written in `module
      # Kernel` arrives at the TOP-LEVEL def path -- which hard-coded "no reopen
      # flag". And the guard lives in the TRAMPOLINE, so a direct call jumped
      # straight past it: a flagged row stands its direct-call nomination down.
      #
      # `before` must be the NATIVE require's answer, from a call written above
      # the reopen. `after` runs the patched body.

      $LOAD_PATH.unshift(File.join(__dir__, "a_unit_reopen_of_kernel_is_positional"))
      require "pkg"
      puts "monitor\t#{Kernel::MONITOR}"
      puts "patched\t#{method(:require).owner}"
    RUBY

    _(result).must_answer <<~'OUT'
      before	false
      after	true
      monitor	monitor
      patched	Kernel
    OUT
  end

  it "unit requires run lazily" do
    result = ze0(<<~'RUBY', files: {"unit_requires_run_lazily/foo/a.rb" => "require_relative \"b\"\nputs \"a body runs\"\nmodule Outer\n  module Foo\n    class A\n      def self.combined = \"a sees \#{B.origin}\"\n    end\n  end\nend\n", "unit_requires_run_lazily/foo/b.rb" => "puts \"b body runs\"\nmodule Outer\n  module Foo\n    class B\n      def self.origin = \"b loaded\"\n    end\n  end\nend\n"})
      # A require INSIDE a lazily-loaded unit runs when the unit body executes --
      # CRuby's order -- rather than being woven inline into whichever unit the
      # sweep reached first (the cross-unit dedup hazard rbconfig hit inside
      # rspec-support's ruby_features.rb). `a.rb` requires `b.rb` at its top, so
      # loading `a` must print b's side effect first, and only at load time.
      module Outer
        module Foo
          def self.install(lib, &require_relative)
            name = "helper_#{lib}"
            (class << self; self; end).__send__(:define_method, name) do |f|
              require_relative.call("unit_requires_run_lazily/#{lib}/#{f}")
            end
          end
          install(:foo) { |f| require_relative(f) }
        end
      end
      puts "before load"
      Outer::Foo.helper_foo "a"
      puts Outer::Foo::A.combined
    RUBY

    _(result).must_answer <<~'OUT'
      before load
      b body runs
      a body runs
      a sees b loaded
    OUT
  end

  it "unit toplevel constant is defined from a class body" do
    result = ze0(<<~'RUBY', files: {"a_unit_toplevel_constant_is_defined_from_a_class_body/latecomer.rb" => "TOP_MARK = \"from the unit\"\n\nmodule Latecomer\n  INSIDE = \"on the module\"\nend\n"})
      # `defined?` on a TOP-LEVEL constant a compiled-in unit assigns, read from
      # inside a class body, answers "constant".
      #
      # A constant whose only assignment lives in a unit cannot be folded -- the
      # unit has not run -- so the read becomes a runtime probe, and the probe is
      # `Search::Scoped`, which deliberately excludes `Object`-owned constants. The
      # owner the emitter guessed was the enclosing class, so a unit's top-level
      # constant was invisible to `defined?` while the READ beside it answered the
      # value: a silent wrong answer, and one that widens with every unit a program
      # compiles in, because the set is keyed by BARE LEAF name.
      #
      # `Object` is probed too, which is the other half of ruby's own rule for a
      # bare constant rather than a widening of it.

      require_relative "a_unit_toplevel_constant_is_defined_from_a_class_body/latecomer" unless defined?(Latecomer)

      class Reader
        def top_defined = defined?(TOP_MARK)
        def top_value = TOP_MARK
        def scoped_defined = defined?(Latecomer::INSIDE)
        def missing_defined = defined?(NEVER_ASSIGNED_ANYWHERE)
      end

      r = Reader.new
      p r.top_defined
      p r.top_value
      p r.scoped_defined
      p r.missing_defined
      # ...and at the top level, where the owner guess was already Object.
      p defined?(TOP_MARK)
      p defined?(Latecomer::INSIDE)
    RUBY

    _(result).must_answer <<~'OUT'
      "constant"
      "from the unit"
      "constant"
      nil
      "constant"
      "constant"
    OUT
  end

  it "unit visibility applies at load" do
    result = ze0(<<~'RUBY', files: {"unit_visibility_applies_at_load/loaded_late.rb" => "class Widget\n  private :prod\n  private_class_method :assemble\nend\n", "unit_visibility_applies_at_load/never_loaded.rb" => "class Widget\n  private :poke\n  private_class_method :fabricate\nend\n"})
      # Visibility directives in a FEATURE UNIT's body apply when the unit LOADS,
      # not at program start: a never-loaded unit's `private` must not fire, and a
      # late-loaded one applies at its load point (CRuby's positional semantics).
      class Widget
        def poke
          "poked"
        end

        def prod
          "prodded"
        end

        def self.fabricate
          "fabricated"
        end

        def self.assemble
          "assembled"
        end
      end

      require_relative "unit_visibility_applies_at_load/never_loaded" if ENV["ZEO_NEVER_SET"]

      w = Widget.new
      p w.poke
      p Widget.fabricate

      p w.prod
      p Widget.assemble

      require_relative "unit_visibility_applies_at_load/loaded_late" if ENV["ZEO_NEVER_SET"].nil?

      begin
        w.prod
      rescue NoMethodError => e
        puts "prod after load: #{e.class}"
      end
      begin
        Widget.assemble
      rescue NoMethodError => e
        puts "assemble after load: #{e.class}"
      end
      p w.send(:prod)
      p Widget.send(:assemble)
    RUBY

    _(result).must_answer <<~'OUT'
      "poked"
      "fabricated"
      "prodded"
      "assembled"
      prod after load: NoMethodError
      assemble after load: NoMethodError
      "prodded"
      "assembled"
    OUT
  end

  it "units module hook does not announce" do
    result = ze0(<<~'RUBY', files: {"a_units_module_hook_does_not_announce/tracer.rb" => "# Loaded only when `Debugger.attach` runs. Everything below is invisible until\n# then -- which is the whole point of the golden beside this file.\nmodule Debugger\n  ANNOUNCED = []\n\n  class ::Module\n    undef method_added\n    def method_added(mid)\n      Debugger::ANNOUNCED << mid\n    end\n  end\nend\n"})
      # A `class ::Module; def method_added` in a file nothing has required yet is
      # not installed, so nothing announces itself to it.
      #
      # Zeo's def-hook pass took a whole-program view: seeing that SOME file defines
      # `method_added` on `Module`, it spliced an announcement beside every `def` in
      # the program. When the file that defines it is a lazily-loaded feature unit,
      # that announcement runs before the hook exists -- and because the same file
      # `undef`s the default row first, the send raised `undefined method
      # 'method_added'` rather than reaching a no-op.
      #
      # rake carries this shape: `rake/application.rb` handles `--debugger` with a
      # method-body `require "debug/session"`, and debug's session file writes
      # `class ::Module; undef method_added; def method_added mid; end`. Merely
      # COMPILING rake made `require "rake"` die inside `fileutils`'s module body.
      #
      # `Module.private_method_defined?(:method_added)` is deliberately NOT printed
      # here: the unit's `undef` is still applied at boot, which is its own gap
      # (`tests/gaps/a_units_undef_of_a_builtin_row_waits_for_the_unit.rb`).

      if ARGV.include?("--debug")
        require_relative "a_units_module_hook_does_not_announce/tracer"
      end

      module Shop
        def self.buy; end
        def sell; end
      end

      class Ledger
        def post; end
        def self.open; end
      end

      p Shop.respond_to?(:buy)
      p Shop.instance_methods(false)
      p Ledger.new.respond_to?(:post)
      p Ledger.respond_to?(:open)
      p defined?(Debugger)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      [:sell]
      true
      true
      nil
    OUT
  end

  it "units superclass can live in a later unit" do
    result = ze0(<<~'RUBY', files: {"a_units_superclass_can_live_in_a_later_unit/child.rb" => "module Store\n  class Child < Path\n    def hi = \"hi\"\n  end\nend\n", "a_units_superclass_can_live_in_a_later_unit/root.rb" => "module Store\n  autoload :Path,  File.expand_path(\"zpath\", __dir__)\n  autoload :Child, File.expand_path(\"child\", __dir__)\nend\n", "a_units_superclass_can_live_in_a_later_unit/settings.rb" => "# The unrelated namespace whose runtime-minted `Path` used to capture\n# every `class X < Path` in the program.\nmodule Settings\n  Path = Struct.new(:explicit, :system) do\n    def kind = \"struct\"\n  end\nend\n", "a_units_superclass_can_live_in_a_later_unit/zpath.rb" => "module Store\n  class Path\n    def kind = \"class\"\n  end\nend\n"})
      # A unit's `class Child < Path` names a superclass another unit defines, and
      # the compiler walks the two in demand order -- which is not load order.
      #
      # `child.rb` lowers before `zpath.rb`, so `Store::Path` is not yet a known
      # class definition when `class Child < Path` lowers. That alone is fine: the
      # forward-shell machinery covers it. What broke was the OTHER half of the same
      # decision -- `settings.rb`'s unrelated `Settings::Path = Struct.new(...) do
      # ... end` answered "yes, `Path` is an assigned constant" for the bare leaf,
      # across the whole program.
      #
      # With one half saying "assigned" and the other saying "not a class here", the
      # `class` keyword was rewritten into a runtime `Child = Class.new(Path)`. The
      # compile-time class then had NO body site at all: it registered, nothing ever
      # revealed it, and the constant read raised while `const_get` answered the
      # runtime class that had taken its place. Two classes, one name.
      #
      # This is `bundler/source/git.rb`'s exact shape -- `class Git < Path` with
      # `Bundler::Settings::Path` elsewhere in the tree -- and it is what made
      # `require "bundler"` die on `Bundler::Source::Git`.

      require_relative "a_units_superclass_can_live_in_a_later_unit/settings"
      require_relative "a_units_superclass_can_live_in_a_later_unit/root"

      p Store::Child
      p Store::Child.superclass
      p Store::Child.new.hi
      p Store::Child.new.kind
      # The read and the reflective lookup must find the SAME class.
      p Store::Child.equal?(Store.const_get(:Child))
      p Store::Path.equal?(Store.const_get(:Path))
      p defined?(Store::Child)
      p Settings::Path.new(1, 2).kind
    RUBY

    _(result).must_answer <<~'OUT'
      Store::Child
      Store::Path
      "hi"
      "class"
      true
      true
      "constant"
      "struct"
    OUT
  end

  it "units undef of a builtin row waits for the unit" do
    result = ze0(<<~'RUBY', files: {"a_units_undef_of_a_builtin_row_waits_for_the_unit/tracer.rb" => "module Debugger\n  class ::Module\n    undef method_added\n    def method_added(mid); end\n  end\nend\n"})
      if ARGV.include?("--debug")
        require_relative "a_units_undef_of_a_builtin_row_waits_for_the_unit/tracer"
      end

      p Module.private_method_defined?(:method_added)
      p Module.private_instance_methods(false).sort.grep(/method_/)
      p Module.new.send(:method_added, :anything)
      p BasicObject.private_method_defined?(:singleton_method_added)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      [:method_added, :method_removed, :method_undefined]
      nil
      true
    OUT
  end
end
