# frozen_string_literal: true

require "spec_helper"

describe "Require programs" do
  it "bundled libraries" do
    result = ze0(<<~'RUBY')
      # ze0 searches the same library tiers `zeo build` does -- the Ruby halves of
      # the runtime's extensions, the pure-Ruby ports, rubygems and bundler, and
      # the store `Gemfile.lock` resolves -- so a plain `require` of a bundled gem
      # reaches one library on both roads.
      require "csv"
      require "forwardable"
      require "tempfile"
      require "abbrev"

      p CSV.generate_line(%w[a b c])
      p Abbrev.abbrev(%w[ruby]).keys.sort

      class Wrapped
        extend Forwardable
        def_delegator :@list, :size
        def initialize(list) = @list = list
      end
      p Wrapped.new([1, 2, 3]).size

      Tempfile.create("ze0") do |f|
        f.write("written")
        f.flush
        p File.read(f.path)
      end

      # `English` aliases a global to a match special, which prism gives a node
      # type of its own.
      require "English"
      "hello world" =~ /o (w\w+)/
      p [$MATCH, $PREMATCH, $POSTMATCH, $LAST_PAREN_MATCH]

      # `tmpdir` puts a module inside its `class Dir` reopen, and a constant
      # inside a `class << obj` body.
      require "tmpdir"
      p Dir.tmpdir.is_a?(String)

      # A spliced file records itself in `$LOADED_FEATURES` before it runs, the
      # way CRuby's `rb_provide_feature` does.
      p $LOADED_FEATURES.any? { |f| f.end_with?("abbrev.rb") }
    RUBY

    _(result).must_answer <<~'OUT'
      "a,b,c\n"
      ["r", "ru", "rub", "ruby"]
      3
      "written"
      ["o world", "hell", "", "world"]
      true
      true
    OUT
  end

  it "features" do
    result = ze0(<<~'RUBY')
      # Test various Ruby features

      # each_with_index
      [10, 20, 30].each_with_index { |v, i|
        puts i.to_s + ":" + v.to_s
      }

      # for..in array
      sum = 0
      for x in [1, 2, 3, 4, 5]
        sum = sum + x
      end
      puts sum

      # for..in range
      s = ""
      for i in 1..5
        s = s + i.to_s
      end
      puts s

      # String#tr
      puts "hello".tr("el", "ip")

      # String#ljust / rjust
      puts "hi".ljust(6) + "|"
      puts "hi".rjust(6) + "|"

      # global variable type check (same type OK)
      $g = 10
      $g = 20
      puts $g
    RUBY

    _(result).must_answer "0:10\n1:20\n2:30\n15\n12345\nhippo\nhi    |\n    hi|\n20\n"
  end

  it "file reached through a symlink loads once" do
    result = ze0(<<~'RUBY', files: {"a_file_reached_through_a_symlink_loads_once/lib/alpha.rb" => "module Alpha\n  LOADS = (defined?(LOADS) ? LOADS : 0) + 1\nend\n", "a_file_reached_through_a_symlink_loads_once/lib/deep/beta.rb" => "Beta = :beta\n", "a_file_reached_through_a_symlink_loads_once/lib/fails.rb" => "require_relative \"deep/beta\"\nraise \"boom\"\n", "a_file_reached_through_a_symlink_loads_once/linked" => {symlink: "lib"}})
      # A require keys a file by its real path too, as CRuby's
      # loaded_features_realpaths does: the same file reached again through a
      # symlinked $LOAD_PATH directory runs no second time, and
      # $LOADED_FEATURES keeps the first spelling. A require that fails leaves
      # out only its own file; what it required on the way stays loaded.

      base = File.join(__dir__, "a_file_reached_through_a_symlink_loads_once")
      require_relative "a_file_reached_through_a_symlink_loads_once/lib/alpha"
      $LOAD_PATH.unshift File.join(base, "linked")
      p require("alpha"), Alpha::LOADS
      p $LOADED_FEATURES.grep(/alpha/).map { |f| f.delete_prefix(base) }

      begin
        require_relative "a_file_reached_through_a_symlink_loads_once/lib/fails"
      rescue => e
        p e.message
      end
      p $LOADED_FEATURES.grep(/fails|beta/).map { |f| f.delete_prefix(base) }
      p require("deep/beta")

    RUBY

    _(result).must_answer <<~'OUT'
      false
      1
      ["/lib/alpha.rb"]
      "boom"
      ["/lib/deep/beta.rb"]
      false
    OUT
  end

  it "gem ruby retired does not load" do
    result = ze0(<<~'RUBY')
      # A library ruby retired from its default and bundled gems, and that no
      # gem installs here, does not load: the require raises LoadError, as in
      # ruby. (webrick left the bundled gems too, but a host can install it.)
      %w[net-telnet sdbm].each do |name|
        begin
          require name
          p [name, :loaded]
        rescue LoadError => e
          p [name, e.class, e.message, e.path]
        end
      end
      p defined?(SDBM)

    RUBY

    _(result).must_answer <<~'OUT'
      ["net-telnet", LoadError, "cannot load such file -- net-telnet", "net-telnet"]
      ["sdbm", LoadError, "cannot load such file -- sdbm", "sdbm"]
      nil
    OUT
  end

  it "issue load path global nil" do
    result = ze0(<<~'RUBY')
      # $LOAD_PATH (and its `$:` alias) should be the Array of require search
      # paths -- zeo leaves it nil instead of populating it.
      p $LOAD_PATH.class
      p $LOAD_PATH.is_a?(Array)
      p $:.class
    RUBY

    _(result).must_answer <<~'OUT'
      Array
      true
      Array
    OUT
  end

  it "load with a wrap argument lowers to a runtime loaderror" do
    result = ze0(<<~'RUBY', files: {"load_with_a_wrap_argument_lowers_to_a_runtime_loaderror/main.rb" => "begin\n  load \"./w.rb\", true\nrescue LoadError => e\n  puts e.message\nend\n", "load_with_a_wrap_argument_lowers_to_a_runtime_loaderror/w.rb" => "puts 1\n"})
      # `load "file", wrap` needs load-time anonymous-module scoping this compiler
      # lacks, so the wrap form lowers to a runtime `Kernel#load` that raises
      # LoadError (the literal no-wrap form is spliced and executed instead).

      Dir.chdir(File.expand_path("load_with_a_wrap_argument_lowers_to_a_runtime_loaderror", __dir__))
      require_relative "load_with_a_wrap_argument_lowers_to_a_runtime_loaderror/main"
    RUBY

    _(result).must_answer "1\n"
  end

  it "Part 1" do
    result = ze0(<<~'RUBY')
      # lrama-required features. Combines what was previously split across
      # lrama_features.rb / _2.rb / _3.rb (the sections were "part 1/2/3"
      # of the same coverage matrix).



      # private (should be ignored)
      class Foo
        def pub; "public"; end
        private
        def priv; "private"; end
      end
      f = Foo.new
      puts f.pub

      # bare case (case without expression)
      x = 5
      result_x = case
                 when x > 10 then "big"
                 when x > 3 then "medium"
                 else "small"
                 end
      puts result_x

      # Array.new(n, val)
      arr_new = Array.new(5, 42)
      puts arr_new.length  # 5
      puts arr_new[0]      # 42
      puts arr_new[4]      # 42

      # Array#compact (no-op for IntArray)
      a2 = [1, 2, 3]
      puts a2.compact.length  # 3

      # Array#flatten (no-op for IntArray)
      puts a2.flatten.length  # 3

      # Array#unshift
      a3 = [2, 3, 4]
      a3.unshift(1)
      puts a3[0]  # 1
      puts a3.length  # 4

      # Array#reverse
      a4 = [1, 2, 3]
      rev = a4.reverse
      puts rev[0]  # 3
      puts rev[2]  # 1

      # Float::INFINITY
      puts Float::INFINITY > 999999  # true

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      public
      medium
      5
      42
      42
      3
      3
      1
      4
      3
      1
      true
      done
    OUT
  end

  it "Part 2" do
    result = ze0(<<~'RUBY')
      # lrama-required features. Combines what was previously split across
      # lrama_features.rb / _2.rb / _3.rb (the sections were "part 1/2/3"
      # of the same coverage matrix).



      # A9: Hash#merge (sp_StrIntHash)
      mrg1 = {"a" => 1, "b" => 2}
      mrg2 = {"b" => 3, "c" => 4}
      mrg3 = mrg1.merge(mrg2)
      puts mrg3["a"]  # 1
      puts mrg3["b"]  # 3  (mrg2 overrides mrg1)
      puts mrg3["c"]  # 4

      # A19: Array#dup
      arr_dup = [10, 20, 30]
      arr_dup2 = arr_dup.dup
      puts arr_dup2[0]  # 10
      puts arr_dup2.length  # 3

      # A19: String#dup (const string)
      sd1 = "hello"
      sd2 = sd1.dup
      puts sd2  # hello

      # A20: Hash.new(0) with default value
      counter = Hash.new(0)
      counter["x"] = counter["x"] + 1
      counter["x"] = counter["x"] + 1
      counter["y"] = counter["y"] + 1
      puts counter["x"]  # 2
      puts counter["y"]  # 1
      puts counter["z"]  # 0 (default)

      # B2: attr_writer
      class Writer
        attr_reader :name
        attr_writer :name
        def initialize(n)
          @name = n
        end
      end
      w = Writer.new("before")
      puts w.name  # before
      w.name = "after"
      puts w.name  # after

      # B3: Comparable (include Comparable + def <=>)
      class Weight
        include Comparable
        attr_reader :grams
        def initialize(g)
          @grams = g
        end
        def <=>(other)
          @grams - other.grams
        end
      end
      w1 = Weight.new(100)
      w2 = Weight.new(200)
      w3 = Weight.new(100)
      puts w1 < w2    # true
      puts w2 > w1    # true
      puts w1 == w3   # true
      puts w1 > w2    # false
      puts w1 <= w3   # true
      puts w2 >= w1   # true

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      1
      3
      4
      10
      3
      hello
      2
      1
      0
      before
      after
      true
      true
      true
      false
      true
      true
      done
    OUT
  end

  it "Part 3" do
    result = ze0(<<~'RUBY')
      # lrama-required features. Combines what was previously split across
      # lrama_features.rb / _2.rb / _3.rb (the sections were "part 1/2/3"
      # of the same coverage matrix).



      # A10: Hash#transform_values (sp_StrIntHash)
      tv = {"a" => 1, "b" => 2, "c" => 3}
      tv2 = tv.transform_values { |v| v * 10 }
      puts tv2["a"]  # 10
      puts tv2["b"]  # 20
      puts tv2["c"]  # 30
      puts tv["a"]   # 1  (original unchanged)

      # A18: Array#zip
      za = [1, 2, 3]
      zb = [4, 5, 6]
      zipped = za.zip(zb)
      puts zipped.length  # 3

      # Zip with different lengths
      zc = [10, 20]
      zipped2 = za.zip(zc)
      puts zipped2.length  # 3

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      10
      20
      30
      1
      3
      3
      done
    OUT
  end

  it "reopening via load twice merges cleanly" do
    result = ze0(<<~'RUBY', files: {"reopening_via_load_twice_merges_cleanly/counter.rb" => "class Counter\n  def bump\n    1\n  end\nend\n", "reopening_via_load_twice_merges_cleanly/main.rb" => "load \"./counter.rb\"\nload \"./counter.rb\"\nputs Counter.new.bump\n"})
      Dir.chdir(File.expand_path("reopening_via_load_twice_merges_cleanly", __dir__))
      require_relative "reopening_via_load_twice_merges_cleanly/main"
    RUBY

    _(result).must_answer "1\n"
  end

  it "require relative" do
    result = ze0(<<~'RUBY', path: "ze0/require_relative.rb", files: {"require_relative/deeper.rb" => "# frozen_string_literal: true\n\n# A required file's top level is its own scope: this `mark` and the one\n# in the file that required it are two names with two slots.\nmark = \"deeper\"\n\nmodule Spliced\n  module Deeper\n    EXTRA = \"+\"\n  end\nend\n\nDEEPER_MARK = mark\n", "require_relative/shared.rb" => "# frozen_string_literal: true\n\nrequire_relative \"deeper\"\n\nmark = \"shared\"\n[\"!\"].each { |s| mark += s }\n\nmodule Spliced\n  MARK = \"!\"\n\n  class Helper\n    def self.help = \"helped\#{Deeper::EXTRA}\#{MARK}\"\n    def self.boom = raise(ArgumentError, \"from the spliced file\")\n  end\nend\n\nSHARED_MARK = mark\n"})
      # frozen_string_literal: true

      # `require_relative` resolves here, not at run time: the target's
      # statements are spliced in at the call's position, once per file.
      # A second require of the same path adds nothing.
      require_relative "require_relative/shared"
      require_relative "require_relative/shared"

      # Each file's top level is its own scope, so all three `mark`s are
      # different names and this one is untouched by the two spliced in above.
      mark = "main"

      module Spliced
        # Reopened from another file: one class row, one body per `module`
        # statement, and the constants of both.
        VERSION = 2

        def self.report = "#{Helper.help} #{VERSION} #{Deeper::EXTRA}"
      end

      p mark, SHARED_MARK, DEEPER_MARK
      p Spliced.report
      p Spliced::Helper.help
      p Spliced::MARK, Spliced::VERSION, Spliced::Deeper::EXTRA
      p Spliced.constants.sort
      p Spliced::Helper.singleton_methods.sort

      begin
        Spliced::Helper.boom
      rescue ArgumentError => e
        # A `def` names the file it was WRITTEN in, not the one being compiled.
        p e.message, e.backtrace.first
      end

      p Spliced::Helper.method(:help).source_location.first

      # A `require` no root carries names a feature the runtime already holds.
      # The backend registers the classes it gates, CONCEALED, and the call
      # opens the gate where it stands. The answer is folded as ruby folds it.
      p require("json")
      p require("json")
      p JSON.name, JSON.instance_of?(Module)
      p require("digest")
      p Digest.name
    RUBY

    _(result).must_answer <<~'OUT'
      "main"
      "shared!"
      "deeper"
      "helped+! 2 +"
      "helped+!"
      "!"
      2
      "+"
      [:Deeper, :Helper, :MARK, :VERSION]
      [:boom, :help]
      "from the spliced file"
      "ze0/require_relative/shared.rb:13:in 'Spliced::Helper.boom'"
      "ze0/require_relative/shared.rb"
      true
      false
      "JSON"
      true
      true
      "Digest"
    OUT
  end

  it "require relative in a method runs when the method does" do
    result = ze0(<<~'RUBY', files: {"a_require_relative_in_a_method_runs_when_the_method_does/counted.rb" => "puts \"counted ran\"\nCOUNTED_RUNS = 1\n", "a_require_relative_in_a_method_runs_when_the_method_does/late.rb" => "puts \"late ran\"\nmodule Late\n  def self.name_of = \"late\"\nend\n"})
      # A `require_relative` written inside a `def` runs when the METHOD runs, not
      # where the file that defines it is loaded. So the target's constants are
      # absent until the first call, the first call answers true and the second
      # false, and a program that never calls the method never loads the file.
      def pull = require_relative("a_require_relative_in_a_method_runs_when_the_method_does/counted")

      p defined?(COUNTED_RUNS)
      p pull
      p pull
      p COUNTED_RUNS

      def never_called = require_relative("a_require_relative_in_a_method_runs_when_the_method_does/late")

      p defined?(Late)
      p never_called
      p Late.name_of
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      counted ran
      true
      false
      1
      nil
      late ran
      true
      "late"
    OUT
  end

  it "stdlib style feature drops in through an i search root" do
    result = ze0(<<~'RUBY', files: {"a_stdlib_style_feature_drops_in_through_an_i_search_root/main.rb" => "require \"shellish\"\nputs Shellish.escape(\"a b c\")\n", "a_stdlib_style_feature_drops_in_through_an_i_search_root/rubylib/shellish.rb" => "module Shellish\n  def self.escape(s)\n    s.gsub(\" \", \"\\\\ \")\n  end\nend\n"})
      # stdlib is delivered as ordinary `-I <lib>` load-path roots (no
      # bespoke flag) -- pointing `-I` at a Ruby checkout's `lib` makes each
      # `require "feature"` resolve a real stdlib `.rb`. This models that with a
      # pure-Ruby "stdlib" file living under an `-I` root, required by name and
      # compiled + run through the ordinary loader path.

      $LOAD_PATH.unshift(File.expand_path("a_stdlib_style_feature_drops_in_through_an_i_search_root/rubylib", __dir__))
      require_relative "a_stdlib_style_feature_drops_in_through_an_i_search_root/main"
    RUBY

    _(result).must_answer "a\\ b\\ c\n"
  end

  it "top level return ends only its file" do
    result = ze0(<<~'RUBY', files: {"a_top_level_return_ends_only_its_file/guarded.rb" => "puts \"guarded: start\"\nif STOPS_MARK\n  begin\n    return\n  rescue StandardError\n    puts \"guarded: rescue\"\n  end\nend\nputs \"guarded: never\"\n", "a_top_level_return_ends_only_its_file/nested.rb" => "puts \"nested: start\"\nrequire_relative \"nested_dep\"\nreturn\nputs \"nested: never\"\n", "a_top_level_return_ends_only_its_file/nested_dep.rb" => "puts \"nested_dep: ran\"\n", "a_top_level_return_ends_only_its_file/never_required.rb" => "puts \"never_required ran\"\n", "a_top_level_return_ends_only_its_file/runs.rb" => "puts \"runs: start\"\nreturn if [].any?\n\nputs \"runs: end\"\n", "a_top_level_return_ends_only_its_file/stops.rb" => "puts \"stops: start\"\nSTOPS_MARK = :set\nreturn if STOPS_MARK\n\nputs \"stops: never\"\nrequire_relative \"never_required\"\n"})
      # ruby's top-level `return` ends the FILE it is written in; reading
      # resumes in the file that required it. zeo ends `<main>` instead, so
      # everything after the first required file's `return` is lost.
      #
      # Each file that writes one gets its own end to jump to, and every later
      # run of that file -- and every run spliced inside it -- is skipped.
      #
      # `crates/zeo-rt/ext/digest/lib/digest.rb:12` opens with a guarded one, and
      # stdlib files use the form to bail out early.

      puts "main: start"
      require_relative "a_top_level_return_ends_only_its_file/stops"
      puts "main: after stops"
      p defined?(STOPS_MARK)
      p defined?(NEVER_REQUIRED)

      require_relative "a_top_level_return_ends_only_its_file/runs"
      puts "main: after runs"

      # It carries through a `require_relative` the returning file writes itself,
      # and out of a `begin`/`rescue` around it.
      require_relative "a_top_level_return_ends_only_its_file/nested"
      puts "main: after nested"
      require_relative "a_top_level_return_ends_only_its_file/guarded"
      puts "main: after guarded"
    RUBY

    _(result).must_answer <<~'OUT'
      main: start
      stops: start
      main: after stops
      "constant"
      nil
      runs: start
      runs: end
      main: after runs
      nested: start
      nested_dep: ran
      main: after nested
      guarded: start
      main: after guarded
    OUT
  end

  it "two files named version each load their own" do
    result = ze0(<<~'RUBY', files: {"two_files_named_version_each_load_their_own/a/lib.rb" => "require_relative \"version\" if ENV[\"NEVER\"]\n\ndef load_a_version\n  require_relative \"version\"\nend\n", "two_files_named_version_each_load_their_own/a/version.rb" => "A_VERSION = \"a\"\n", "two_files_named_version_each_load_their_own/b/lib.rb" => "require_relative \"version\" if ENV[\"NEVER\"]\n\ndef load_b_version\n  require_relative \"version\"\nend\n", "two_files_named_version_each_load_their_own/b/version.rb" => "B_VERSION = \"b\"\n"})
      # Two compiled-in files can share a basename, and each `require_relative
      # "version"` must load ITS OWN sibling.
      #
      # `zeo_rt::features::UNITS` is a map, so a unit registered under a bare
      # relative spelling is a COLLISION rather than an alias -- one file silently
      # answers for the other, the require reports success, and the feature is
      # recorded loaded so no later require can recover. That is exactly what
      # `pub_grub/static_package_source.rb`'s `require_relative 'rubygems'` did to
      # `require "rubygems"`.
      #
      # A `require_relative` therefore registers its unit under the target's
      # ABSOLUTE spelling, which is what the runtime `require_relative` builds
      # before it asks. The compiler also warns now when two units claim one
      # spelling anyway, and the runtime keeps the FIRST claim so the warning names
      # the file that really lost.
      #
      # Eight files are named `version.rb` across the vendored rubygems and bundler
      # trees alone, so this is a shape, not a curiosity.

      require_relative "two_files_named_version_each_load_their_own/a/lib"
      require_relative "two_files_named_version_each_load_their_own/b/lib"

      p load_a_version
      p load_b_version
      p [A_VERSION, B_VERSION]
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      ["a", "b"]
    OUT
  end

  it "unsupported feature diagnostics" do
    result = ze0(<<~'RUBY')
      # A deliberately-unsupported feature (docs/limitations.md) names itself rather
      # than dumping compiler internals. A user-defined method of the same name is
      # that method, not the builtin, so it still works (#2652 / #2667 / #2668).
      class Dsl
        def extend(x); "user-extend:#{x}"; end
        def ruby2_keywords; "user-r2k"; end
        def define_singleton_method(n); "user-dsm:#{n}"; end
        def refine(x); "user-refine:#{x}"; end
        def using(x); "user-using:#{x}"; end
        def include(x); "user-include:#{x}"; end
        def set_trace_func(x); "user-stf:#{x}"; end
      end
      d = Dsl.new
      p d.extend(1)
      p d.ruby2_keywords
      p d.define_singleton_method(:z)
      p d.refine(1)
      p d.using(2)
      p d.include(3)
      p d.set_trace_func(4)
      def extend(a); "toplevel:#{a}"; end
      p extend(9)

      # a user-defined SINGLETON method of a limited name is that method too:
      # `Mod.prepend(kwargs)` resolves to `def self.prepend`, not Module#prepend (#2712)
      module Broadcasts
        def self.prepend(stream:, target:, html:)
          "#{stream}/#{target}/#{html}"
        end
        def self.replace(x); "rep:#{x}"; end
      end
      puts Broadcasts.prepend(stream: "articles", target: "articles", html: "<div/>")
      puts Broadcasts.replace(1)

      # the compile-time forms these limits point you at keep working
      module Mx; def mm; "mm"; end; end
      class Ok; include Mx; attr_accessor :v; end
      o = Ok.new
      o.v = 7
      p o.v
      p o.mm
      p Ok.new.is_a?(Mx)

      # binding is NOT in the unsupported set: local_variable_get works
      x = 42
      p binding.local_variable_get(:x)
    RUBY

    _(result).must_answer <<~'OUT'
      "user-extend:1"
      "user-r2k"
      "user-dsm:z"
      "user-refine:1"
      "user-using:2"
      "user-include:3"
      "user-stf:4"
      "toplevel:9"
      articles/articles/<div/>
      rep:1
      7
      "mm"
      true
      42
    OUT
  end

  it "write payload untyped" do
    result = ze0(<<~'RUBY')
      # A write payload the analysis types as neither String nor poly: `@wrk.pack("C*")`
      # on a nilable ivar is a C string typed TY_UNKNOWN. Boxing one renders it as
      # "evaluate for effect, yield nil", so the payload slots have to keep the String
      # rendering for it -- optcarrot's ROM#save_battery is exactly this shape, and
      # boxing it wrote an empty file.
      require "stringio"

      dir = "/tmp/spinel_write_payload_untyped"
      if Dir.exist?(dir)
        Dir.children(dir).each { |e| File.delete("#{dir}/#{e}") }
        Dir.rmdir(dir)
      end
      Dir.mkdir(dir)

      class Battery
        def initialize(n)
          @wrk = n > 0 ? (65..67).map { |a| a } : nil
        end

        def save(path)
          File.binwrite(path, @wrk.pack("C*"))
        end

        def save_text(path)
          File.write(path, @wrk.pack("C*"))
        end

        def into(io)
          io.write(@wrk.pack("C*"))
        end
      end

      b = Battery.new(1)

      bin = "#{dir}/battery.sav"
      p b.save(bin)
      p File.read(bin)

      txt = "#{dir}/battery.txt"
      p b.save_text(txt)
      p File.read(txt)

      io = StringIO.new
      b.into(io)
      p io.string

      Dir.children(dir).each { |e| File.delete("#{dir}/#{e}") }
      Dir.rmdir(dir)
    RUBY

    _(result).must_answer <<~'OUT'
      3
      "ABC"
      3
      "ABC"
      "ABC"
    OUT
  end
end
