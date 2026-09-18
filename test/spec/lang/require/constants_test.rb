# frozen_string_literal: true

require "spec_helper"

describe "Require: constants" do
  it "autoload" do
    result = ze0(<<~'RUBY')
      # frozen_string_literal: true

      # `autoload :C, "feature"` names a file that PROVIDES `C`. ze0 has no
      # lazy units, so the file is spliced in and the constant is there before
      # anything asks for it -- zeo's own stated divergence from CRuby: the
      # file runs at the `autoload` statement rather than at first constant
      # access, and even if the constant is never referenced.
      #
      # A feature no load path carries is one the runtime already holds, and
      # the declaration opens its gate where it stands.

      autoload :JSON, "json"

      p JSON.name
      p JSON.instance_of?(Module)

      # The declaration itself answers nil.
      p(autoload(:JSON, "json"))
    RUBY

    _(result).must_answer <<~'OUT'
      "JSON"
      true
      nil
    OUT
  end

  it "autoload dsl computes its own path" do
    result = ze0(<<~'RUBY', files: {"autoload_dsl/mylib/model.rb" => "module MyLib\n  class Model\n    def self.hello\n      \"model loaded\"\n    end\n  end\nend\n", "autoload_dsl/mylib.rb" => "module MyLib\n  # `ActiveSupport::Autoload`'s shape, in miniature: an `autoload` written in\n  # plain Ruby that derives the path from the constant and hands it to the real\n  # `Module#autoload` through `super`. Nothing here is known to the compiler --\n  # the string only exists while the program runs.\n  module Autoload\n    def autoload(const_name, path = nil)\n      path ||= File.expand_path(\"mylib/\#{const_name.to_s.downcase}\", __dir__)\n      super const_name, path\n    end\n  end\n\n  extend Autoload\n\n  autoload :Model\nend\n"})
      require_relative "autoload_dsl/mylib"

      puts MyLib::Model.hello
      puts MyLib::Model.name
      puts defined?(MyLib::Model)
    RUBY

    _(result).must_answer <<~'OUT'
      model loaded
      MyLib::Model
      constant
    OUT
  end

  it "autoload is defined before it loads" do
    result = ze0(<<~'RUBY', files: fixtures("autoload_target/autoload_deep.rb", "autoload_target/autoload_gadget.rb", "autoload_target/autoload_quiet.rb", "autoload_target/autoload_thing.rb", "autoload_target/autoload_widget.rb"))
      # `defined?` and `const_defined?` announce an `autoload`ed constant the moment
      # the `autoload` is written -- and a NESTED ask loads the file to answer.
      #
      # zeo answered nil to both, and the consequence was not abstract:
      # `rubygems/openssl.rb` is
      #
      #     autoload :OpenSSL, "openssl"
      #     HAVE_OPENSSL = defined? OpenSSL::SSL
      #
      # so rubygems concluded it had no OpenSSL and refused every HTTPS source with
      # "OpenSSL is not available. Install OpenSSL and rebuild Ruby".
      #
      # The two asks differ, which is the whole subtlety: a BARE `defined?(A)` says
      # "constant" WITHOUT running the autoload, and `defined?(A::B)` runs it,
      # because resolving the head is a real constant read.
      #
      # The target is named by a string the compiler cannot resolve, so the
      # binary carries the compiler and the first read requires the feature
      # under the $LOAD_PATH the program has built by then.

      DIR = File.expand_path("../../fixtures/autoload_target", __dir__)
      $LOAD_PATH.unshift(DIR)

      module Bare
        autoload :Widget, "autoload_widget"
      end

      puts "bare defined?\t#{defined?(Bare::Widget).inspect}"
      puts "const_defined?\t#{Bare.const_defined?(:Widget)}"
      puts "autoload?\t#{Bare.autoload?(:Widget).inspect}"

      module Nested
        autoload :Deep, "autoload_deep"
      end

      # The head has not run yet, so nothing knows about `Deep::Inner`...
      puts "before\t#{$autoload_deep_loaded.inspect}"
      # ...and asking loads it.
      puts "nested defined?\t#{defined?(Nested::Deep::Inner).inspect}"
      puts "after\t#{$autoload_deep_loaded.inspect}"
      puts "missing nested\t#{defined?(Nested::Deep::Absent).inspect}"

      # A bare ask does NOT load. Fresh module, fresh target.
      module Untouched
        autoload :Quiet, "autoload_quiet"
      end
      puts "bare ask\t#{defined?(Untouched::Quiet).inspect}"
      puts "still unloaded\t#{$autoload_quiet_loaded.inspect}"

      # Reading it for real is what runs it.
      Untouched::Quiet
      puts "after read\t#{$autoload_quiet_loaded.inspect}"
    RUBY

    _(result).must_answer <<~'OUT'
      bare defined?	"constant"
      const_defined?	true
      autoload?	"autoload_widget"
      before	nil
      nested defined?	"constant"
      after	true
      missing nested	nil
      bare ask	"constant"
      still unloaded	nil
      after read	true
    OUT
  end

  it "autoload paths" do
    result = ze0(<<~'RUBY', files: {"autoload_paths/base.rb" => "puts \"base ran\"\n\nclass PathBase\n  LIMIT = 7\n  def limit = LIMIT\nend\n", "autoload_paths/target.rb" => "puts \"target ran\"\n\nmodule Paths\n  class Widget\n    KIND = :widget\n    def kind = KIND\n  end\nend\n"})
      # frozen_string_literal: true

      # An `autoload` target the compile can NAME becomes a lazily linked unit
      # and the declaration stays a real call, so the file runs when the
      # constant is first read -- CRuby's own order. Three spellings resolve
      # here: a plain feature, `"#{__dir__}/..."` and
      # `File.expand_path("...", __dir__)`.
      #
      # A superclass clause is a read too, and so is the receiver of a `Foo.new`
      # the compile constructs directly.

      module Paths
        autoload :Widget, "#{__dir__}/autoload_paths/target"
      end

      autoload :PathBase, File.expand_path("autoload_paths/base", __dir__)

      puts "before the read"
      p Paths.autoload?(:Widget) != nil
      p Paths::Widget.new.kind
      p Paths.autoload?(:Widget)

      class PathSub < PathBase
      end
      p PathSub.new.limit
      p PathSub.superclass
    RUBY

    _(result).must_answer <<~'OUT'
      before the read
      true
      target ran
      :widget
      nil
      base ran
      7
      PathBase
    OUT
  end

  it "autoload runs when its constant is read" do
    result = ze0(<<~'RUBY', files: fixtures("autoload_target/autoload_deep.rb", "autoload_target/autoload_gadget.rb", "autoload_target/autoload_quiet.rb", "autoload_target/autoload_thing.rb", "autoload_target/autoload_widget.rb"))
      # Reading a constant is what RUNS its `autoload`.
      #
      # zeo recorded the target and never ran it, except for the one internal case
      # of a concealed builtin class. So every `autoload` a gem declared was a
      # `LoadError` waiting to happen: the read went straight to `const_missing`,
      # which found the record and raised the error the load was never given a
      # chance to avoid. rubygems declares every one of its classes this way.
      #
      # The target is named by a string the compiler cannot resolve, so the
      # binary carries the compiler and the first read requires the feature
      # under the $LOAD_PATH the program has built by then.

      DIR = File.expand_path("../../fixtures/autoload_target", __dir__)

      # --- the plain case, by feature name --------------------------------------
      $LOAD_PATH.unshift(DIR)

      module ByFeature
        autoload :Widget, "autoload_widget"
      end

      puts "before\t#{ByFeature.const_defined?(:Widget)}"
      puts "autoload?\t#{ByFeature.autoload?(:Widget)}"
      puts "read\t#{ByFeature::Widget}"
      puts "value\t#{ByFeature::Widget.new.name}"
      # Spent once it has run.
      puts "after\t#{ByFeature.autoload?(:Widget).inspect}"

      # --- by ABSOLUTE path, which is how rubygems writes it --------------------
      module ByPath
        autoload :Gadget, File.expand_path("autoload_gadget", DIR)
      end

      puts "path read\t#{ByPath::Gadget}"
      puts "path value\t#{ByPath::Gadget.new.name}"

      # --- const_get reaches it too, including through a scoped name ------------
      module Scoped
        autoload :Thing, "autoload_thing"
      end

      puts "const_get\t#{Object.const_get('Scoped::Thing')}"

      # --- a target that does not exist still raises LoadError ------------------
      module Missing
        autoload :Nothing, "no_such_file_anywhere"
      end

      begin
        Missing::Nothing
      rescue LoadError => e
        puts "missing\tLoadError"
      end

      # --- reading twice does not load twice ------------------------------------
      puts "count\t#{$autoload_widget_loads}"
      ByFeature::Widget
      puts "count again\t#{$autoload_widget_loads}"
    RUBY

    _(result).must_answer <<~'OUT'
      before	true
      autoload?	autoload_widget
      read	ByFeature::Widget
      value	widget
      after	nil
      path read	ByPath::Gadget
      path value	gadget
      const_get	Scoped::Thing
      missing	LoadError
      count	1
      count again	1
    OUT
  end

  it "autoload target that never loads fails at the constant" do
    result = ze0(<<~'RUBY')
      # `autoload` registers a hook; it does not touch the file. So a target that is
      # not on the load path is not an error at the declaration -- it is an error
      # when the constant is READ, and most such constants never are. actionpack
      # writes `autoload :Test, "rack/test"` in every program that loads
      # action_dispatch, and rack-test is frequently not there.
      #
      # The constant is announced at declaration all the same, which is what
      # `const_defined?` and `autoload?` report.
      module Holder
        autoload :Absent, "definitely_no_such_feature_xyz"
        Present = 1
      end

      p Holder::Present
      p Holder.autoload?(:Absent)
      p Holder.const_defined?(:Absent)
      p Holder.constants.include?(:Present)

      begin
        Holder::Absent
      rescue LoadError => e
        puts "LoadError: #{e.message}"
      end

      # Reading it again asks the same question again, and gets the same answer.
      begin
        Holder.const_get(:Absent)
      rescue LoadError => e
        puts "LoadError: #{e.message}"
      end

      puts "still running"
    RUBY

    _(result).must_answer <<~'OUT'
      1
      "definitely_no_such_feature_xyz"
      true
      true
      LoadError: cannot load such file -- definitely_no_such_feature_xyz
      LoadError: cannot load such file -- definitely_no_such_feature_xyz
      still running
    OUT
  end

  it "compact module path keys its autoload" do
    result = ze0(<<~'RUBY', files: {"compact_module/target.rb" => "puts \"target.rb ran\"\nmodule Deep\n  module Nest\n    class Widget\n      KIND = :widget\n      class << self\n        def kind = KIND\n      end\n    end\n  end\nend\n"})
      # `module A::B` -- the COMPACT form -- contributes both segments to the
      # lexical path a constant inside it hangs off. The autoload collector read
      # prism's `name` on that node, which is the LAST segment alone, so it keyed
      # `autoload :Widget, "..."` under `Nest::Widget` where the read resolves
      # `Deep::Nest::Widget`. Nothing ever matched, and the read that should have
      # run the target did nothing -- silently, because a compiled-in unit's
      # classes are in the dispatch tables from startup. `Deep::Nest::Widget`
      # resolved and `.kind` was callable; only the body's constant was missing.
      #
      # rspec-core writes `module RSpec::Core::Formatters` and declares nine
      # formatter autoloads inside it, so none of them ever loaded: reading
      # `ProgressFormatter` gave a class whose body had never run, and nothing had
      # registered it as a formatter.

      module Deep
        module Nest
        end
      end

      module Deep::Nest
        autoload :Widget, "#{__dir__}/compact_module/target"
      end

      puts "before read"
      p Deep::Nest.autoload?(:Widget) != nil
      p Deep::Nest::Widget.kind
      p Deep::Nest.autoload?(:Widget) != nil
    RUBY

    _(result).must_answer <<~'OUT'
      before read
      true
      target.rb ran
      :widget
      false
    OUT
  end

  it "nested autoload names a builtin" do
    result = ze0(<<~'RUBY')
      # frozen_string_literal: true

      # Two things an `autoload` naming a GATED builtin feature gets wrong.
      #
      # A top-level one does not mark the feature LOADED, so a later `require`
      # of it answers true where ruby answers false. One written in a class
      # body never opens the gate at all, so the constant is missing.

      autoload :JSON, "json"
      p require("json")

      class Store
        autoload :Digest, "digest"

        def digest = Digest.name
      end

      p Store.new.digest
    RUBY

    _(result).must_answer <<~'OUT'
      true
      "Digest"
    OUT
  end

  it "nested read under an autoload runs the target" do
    result = ze0(<<~'RUBY', files: {"autoload_nested/ns.rb" => "puts \"  ns.rb body ran\"\nmodule NS\n  LOADED = true\n  module Inner\n    class Deep\n      def self.hi = \"deep\"\n    end\n  end\nend\n"})
      # An `autoload` names a NAMESPACE far more often than it names the leaf a
      # program reads: net/http writes `autoload :OpenSSL, "openssl"` and then reads
      # `OpenSSL::SSL::SSLContext`. The read has to run the target, so the gate at
      # the fold has to fire on every PREFIX of the path, not on the whole of it.
      #
      # Keying only on the whole path never fired here, and the read found a class
      # whose unit had not run -- `uninitialized constant OpenSSL::SSL::SSLContext`
      # from inside `Net::HTTP#connect`. Caught by an HTTPS request, not by the
      # corpus, which is why this shape is a golden now.
      $LOAD_PATH.unshift(File.expand_path("autoload_nested", __dir__))

      puts "before"
      autoload :NS, File.expand_path("autoload_nested/ns", __dir__)
      puts "after the declaration"

      # Nothing has run yet.
      p Object.autoload?(:NS)&.end_with?("ns")

      # A read three levels down the namespace must run it.
      puts "first read"
      p NS::Inner::Deep.hi
      p NS::LOADED
      p Object.autoload?(:NS)
    RUBY

    _(result).must_answer <<~'OUT'
      before
      after the declaration
      true
      first read
        ns.rb body ran
      "deep"
      true
      nil
    OUT
  end

  it "superclass reference runs its autoload" do
    result = ze0(<<~'RUBY', files: {"superclass_reference/base.rb" => "puts \"base.rb ran\"\nclass Base\n  LIMIT = 7\n  def limit = LIMIT\nend\n", "superclass_reference/sub.rb" => "class Sub < Base\nend\n"})
      # `class Sub < Base` READS the constant `Base`, and a read is what runs an
      # `autoload` target. zeo resolves the superclass edge at compile time, so the
      # read had no run-time half at all: `sub.rb` linked to a `Base` whose body had
      # never run, and `Base#limit` raised `uninitialized constant Base::LIMIT` for a
      # constant the body assigns.
      #
      # bundler is the case. `plugin/dsl.rb` requires nothing: `class DSL <
      # Bundler::Dsl` is the only thing that loads `bundler/dsl.rb`, and that file's
      # class body is where `VALID_KEYS` comes from -- so `bundle install` died in
      # `Dsl#git_source` before it read the Gemfile.

      autoload :Base, "#{__dir__}/superclass_reference/base"
      require_relative "superclass_reference/sub"
      p Sub.new.limit
      p Sub.superclass
    RUBY

    _(result).must_answer <<~'OUT'
      base.rb ran
      7
      Base
    OUT
  end
end
