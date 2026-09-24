# frozen_string_literal: true

require "spec_helper"

describe "RubyGems programs" do
  it "bundler registers its thor commands" do
    result = zr(<<~'RUBY')
      # MILESTONE: bundler's whole command table, which Thor builds through
      # `method_added`.
      #
      # `Bundler::Thor::Base::ClassMethods#method_added` turns each `def` in
      # `Bundler::CLI` into a registered command. zr refused every one of those
      # announcements: `analyze::def_hooks::fires` cannot order a hook against a
      # definition in ANOTHER file, and thor and the CLI are different files. So
      # `Bundler::CLI` kept 3 of its ~30 commands -- the three `register` adds
      # directly -- and `zr bundle install` answered `Could not find command
      # "install"`.
      #
      # A require GRAPH orders them. `bundler/cli.rb` opens with `require_relative
      # "vendored_thor"` and declares `class CLI < Thor` below it, so thor has run
      # whole by the time any of those definitions execute -- a fact, not a guess
      # about unit order.
      #
      # This lived as a gap file, where it proved nothing: compiling bundler needs
      # more than the golden tier's 512 MiB child bound, so the run was KILLED and
      # the gap "passed" on a divergence that was really a dead child. The milestone
      # tier is where a whole-graph compile belongs.
      #
      # Shapes, never versions.

      require "bundler"
      require "bundler/cli"

      commands = Bundler::CLI.commands
      p commands.keys.size >= 30
      %w[install update exec check config list show info add remove lock].each do |name|
        p [name, commands.key?(name)]
      end
      p Bundler::CLI.all_commands.key?("install")

      # Thor runs a command only when the instance reports it PUBLIC, which asks
      # `private_methods` -- and `exec` is also a private `Kernel` method, so a name
      # left unclaimed by the class that defines it reads back as private.
      p Bundler::CLI.private_instance_methods.include?(:exec)
      p Bundler::CLI.public_instance_methods.include?(:exec)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      ["install", true]
      ["update", true]
      ["exec", true]
      ["check", true]
      ["config", true]
      ["list", true]
      ["show", true]
      ["info", true]
      ["add", true]
      ["remove", true]
      ["lock", true]
      true
      false
      true
    OUT
  end

  it "computed require of a bundled gem" do
    result = zr(<<~'RUBY')
      # `x = ["json", ""].first; require x` loads json, exactly as the same require
      # spelled literally does.
      #
      # This was a recorded divergence, and the reasoning it carried was half right.
      # It said the automatic tiers could not reach a bundled gem: the eager unit
      # sweep compiles in files on a COMPILE-TIME load path and a bundled gem is not
      # on one, while the run-time tier searches `$LOAD_PATH` on disk and a compiled
      # binary carries no path to a gem that was never installed on the machine.
      # Both true, and both beside the point for json.
      #
      # json is a NATIVE feature: its native half is linked into the binary and
      # registered before line 1, which is why a literal `require "json"` folds to
      # nothing but a loaded-feature marker. Nothing has to be found, embedded or
      # compiled -- the answer was already in the process, and the run-time require
      # simply did not know to look. It does now, and the compiler registers every
      # gated builtin CONCEALED for a program with a computed require, so `JSON`
      # starts absent and this line reveals it.
      #
      # `--embed-sources` is still the answer for a gem that really is only Ruby
      # source. The neighbours still say how the rest is covered: a computed
      # require of a file under a compile-time `-I` root works through the unit
      # sweep, and one on the run-time `$LOAD_PATH` works through the disk tier.
      name = ["json", ""].first
      require name
      p JSON.generate([1, 2])

      # Registering every gated builtin for this program does NOT reveal them: a
      # feature nothing required keeps its constant absent, which is ruby's rule.
      begin
        Object.const_get("StringScanner")
        puts "revealed early"
      rescue NameError
        puts "still absent"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      "[1,2]"
      still absent
    OUT
  end

  it "gemspec loads from yaml" do
    result = zr(<<~'RUBY')
      # MILESTONE: a real `Gem::Specification` comes back out of YAML.
      #
      # This is the shape a `.gem` archive carries in its `metadata.gz`, and reading
      # it is the single thing that stood between zr and opening one. Before the
      # `!ruby/object:` revival landed, the document loaded as a plain Hash and
      # rubygems answered "YAML data doesn't evaluate to gem specification".
      #
      # The rung that makes it work is `init_with`: `Gem::Specification` defines one
      # that forwards to its own `yaml_initialize`, so psych hands it a
      # `Psych::Coder` and rubygems does the rest -- including coercing `date` and
      # rebuilding `Gem::Version` from its own nested `!ruby/object:`.
      #
      # Shapes, never versions.

      # Nothing is required but rubygems itself. `Gem::Version`, `Gem::Dependency`
      # and `Gem::Requirement` all arrive through rubygems' own `autoload`, which is
      # how a real caller meets them -- and which zr could not run at all until the
      # read path was given the chance to.
      require "yaml"
      require "rubygems"

      YAML_TEXT = <<~Y
        --- !ruby/object:Gem::Specification
        name: widget
        version: !ruby/object:Gem::Version
          version: 1.2.3
        platform: ruby
        authors:
        - Someone
        date: 2026-08-28 00:00:00.000000000 Z
        dependencies:
        - !ruby/object:Gem::Dependency
          name: rake
          requirement: !ruby/object:Gem::Requirement
            requirements:
            - - ">="
              - !ruby/object:Gem::Version
                version: '0'
          type: :development
        summary: a widget
        require_paths:
        - lib
        files:
        - lib/widget.rb
      Y

      spec = Gem::Specification.from_yaml(YAML_TEXT)

      puts spec.class
      puts spec.name
      puts spec.version.class
      puts spec.version.to_s
      puts spec.summary
      puts spec.authors.inspect
      puts spec.require_paths.inspect
      puts spec.files.inspect
      puts spec.platform.to_s

      dep = spec.dependencies.first
      puts dep.class
      puts dep.name
      puts dep.type.inspect
      puts dep.requirement.to_s

      # The nested revival went all the way down: every one of these is an object
      # rather than the Hash it was written as.
      puts spec.dependencies.map { |d| d.requirement.requirements.first.last.class }.inspect
    RUBY

    _(result).must_answer <<~'OUT'
      Gem::Specification
      widget
      Gem::Version
      1.2.3
      a widget
      ["Someone"]
      ["lib"]
      ["lib/widget.rb"]
      ruby
      Gem::Dependency
      rake
      :development
      >= 0
      [Gem::Version]
    OUT
  end

  it "is there before the first line" do
    result = zr(<<~'RUBY')
      # ruby loads rubygems before a program's first line: Gem answers without
      # a require, `require "rubygems"` answers false, and Kernel#require and
      # #gem are rubygems' own. A String compares with a Gem::Version through
      # the version's own <=>.
      p defined?(Gem), require("rubygems"), $LOADED_FEATURES.any? { |feature| feature.end_with?("/rubygems.rb") }
      p Kernel.private_instance_methods.include?(:gem), Kernel.private_instance_methods.include?(:gem_original_require)
      p Gem::Version.new("1.10") > Gem::Version.new("1.9"), "9.0" < Gem::Version.new("10.0")
      p Gem.loaded_specs.class, Gem::Requirement.new("~> 1.2").satisfied_by?(Gem::Version.new("1.5"))
      p Gem::Platform.local.os.empty?

    RUBY

    _(result).must_answer <<~'OUT'
      "constant"
      false
      true
      true
      true
      true
      true
      Hash
      true
      false
    OUT
  end

  it "require rubygems under a guard" do
    result = zr(<<~'RUBY')
      # MILESTONE: `require "rubygems" unless defined?(Gem)` loads RUBYGEMS.
      #
      # The idiom `bundler/rubygems_ext.rb:3` opens with, and the shape that made
      # zr run a completely different file while answering true.
      #
      # A guarded require takes the UNIT path where an unguarded one takes the
      # splice path, and a unit is keyed in a global table by the spelling that
      # demanded it. A `require_relative`'s spelling is RELATIVE, so recording it as
      # written put the bare name `rubygems` in that table --  and four files under
      # `gems/` are named `rubygems.rb`. pub_grub's `static_package_source.rb` says
      # `require_relative 'rubygems'`, so its file claimed the global spelling and
      # silently shadowed RubyGems itself: `require "rubygems"` ran
      # `Bundler::PubGrub::RubyGems`, returned true, recorded the feature as loaded
      # so no later require could recover, and left `Gem` undefined.
      #
      # Shapes, never versions.

      require "rubygems" unless defined?(Gem)

      p defined?(Gem)
      p Gem::VERSION.is_a?(String)
      p Gem::Requirement.default.to_s
      p Gem::Version.new("1.2.3").to_s

      # NOT `defined?(Bundler)`: the oracle runs with `-rbundler/setup`, so bundler
      # is loaded before any program it records starts. The question cannot be asked
      # neutrally under it, and the answer recorded here would be the harness's
      # rather than the program's.

      # ...and a second require answers false, having really loaded the first time.
      p require("rubygems")
    RUBY

    _(result).must_answer <<~'OUT'
      "constant"
      true
      ">= 0"
      "1.2.3"
      false
    OUT
  end

  it "requiring rubygems then bundler installs the monkeypatches without a warning ruby does not print" do
    result = zr(<<~'RUBY')
      # MILESTONE: `require "rubygems"` then `require "bundler"`, and the bundler
      # monkeypatches over RubyGems that the second require installs.
      #
      # The stdout matched long before the stderr did. What kept this XFAIL was 24
      # `already initialized constant Gem::Platform::X` warnings ruby does not
      # print: `bundler/rubygems_ext.rb:54`'s `class Platform` body is a single
      # `unless respond_to?(:generic)` statement, and codegen used to lift a
      # sole-statement class-body guard out into the enclosing scope. Asked of `Gem`
      # the probe answered false, so twelve constants `rubygems/platform.rb` had
      # already written were written again. See
      # `tests/a_class_body_guard_asks_about_the_class.rb`.
      #
      # A golden compares stdout AND stderr, which is what kept this honest.
      #
      # Shapes, never versions.

      require "rubygems"
      require "bundler"

      p defined?(Gem)
      p defined?(Bundler)
      p Bundler::VERSION.is_a?(String)
      p Bundler.respond_to?(:setup)
      p Bundler.gem_version.is_a?(Gem::Version)

      # Bundler's monkeypatches over RubyGems landed.
      p Gem::Specification.new.respond_to?(:source)
      p Gem::Platform.respond_to?(:generic)
      p Gem::Platform.generic(Gem::Platform::RUBY).to_s

      # The lockfile reader -- pure text, and what every `bundle` command starts at.
      lock = <<~LOCK
        GEM
          remote: https://rubygems.org/
          specs:
            rake (13.2.1)
            minitest (5.25.1)

        PLATFORMS
          ruby

        DEPENDENCIES
          minitest (~> 5.0)
          rake

        BUNDLED WITH
           2.5.0
      LOCK
      parsed = Bundler::LockfileParser.new(lock)
      p parsed.specs.map { |s| [s.name, s.version.to_s] }.sort
      p parsed.platforms.map(&:to_s)
      p parsed.dependencies.keys.sort
      p parsed.bundler_version.to_s
    RUBY

    _(result).must_answer <<~'OUT'
      "constant"
      "constant"
      true
      true
      true
      true
      true
      "ruby"
      [["minitest", "5.25.1"], ["rake", "13.2.1"]]
      ["ruby"]
      ["minitest", "rake"]
      "2.5.0"
    OUT
  end

  it "a specification reads its date from the frozen source date epoch" do
    result = zr(<<~'RUBY', env: { "SOURCE_DATE_EPOCH" => "86400" })
      require "rubygems"
      e = Gem.source_date_epoch
      p e.frozen?, e.utc.equal?(e)
      s = Gem::Specification.new { |x| x.name = "a"; x.version = "1" }
      p s.date, s.date.utc?
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      1970-01-02 00:00:00 UTC
      true
    OUT
  end
end
