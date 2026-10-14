# frozen_string_literal: true

module Zr
  module Dev
    # Where a generator reads the C sources that zr's tables come from.
    # `RUBY_SRC` names a CRuby checkout that holds RUBY_REVISION, and
    # `PRISM_SRC` a prism checkout that holds prism_revision. Neither is
    # vendored: a table is written from them once and then committed.
    # `RUBY_SRC`, else tmp/ruby.
    def self.ruby_src
      return File.expand_path(ENV["RUBY_SRC"]) unless ENV["RUBY_SRC"].to_s.empty?

      path("tmp/ruby")
    end

    # Whether a CRuby checkout is at hand.
    def self.ruby_src? = File.directory?(ruby_src)

    # `PRISM_SRC`, else tmp/prism.
    def self.prism_src
      return File.expand_path(ENV["PRISM_SRC"]) unless ENV["PRISM_SRC"].to_s.empty?

      path("tmp/prism")
    end

    # The prism commit that ruby bundles: the fourth column of prism's row
    # in CRuby's gems/bundled_gems at RUBY_REVISION. ruby's build makes
    # the prism gem from that commit, and its parser is that commit's C.
    def self.prism_revision
      row = cruby("gems/bundled_gems").lines.find { |line| line.split.first == "prism" }
      row&.split&.[](3) or fail!("zr-dev: ruby's gems/bundled_gems gives no git commit for prism")
    end

    # One CRuby source file at RUBY_REVISION.
    def self.cruby(path) = git_show(ruby_src, RUBY_REVISION, path, "RUBY_SRC")

    # The files below `dir` of CRuby at RUBY_REVISION.
    def self.cruby_files(dir)
      git("ls-tree", "--name-only", "#{RUBY_REVISION}:#{dir}", dir: ruby_src, err: $stderr).to_s.split("\n")
    end

    # One prism source file at prism_revision.
    def self.prism(path) = git_show(prism_src, prism_revision, path, "PRISM_SRC")

    # Whether a prism checkout is at hand.
    def self.prism? = File.exist?(File.join(prism_src, ".git"))

    def self.git_show(checkout, revision, path, variable)
      unless File.directory?(checkout)
        fail!("zr-dev: no checkout at #{checkout}. Run 'ruby .github/scripts/fetch_sources.rb', or set #{variable} to a checkout")
      end
      text = git("show", "#{revision}:#{path}", dir: checkout)
      return text if text

      fail!("zr-dev: no #{path} at #{revision[0, 12]} in #{checkout}; #{variable} names a checkout that has it")
    end
  end
end
