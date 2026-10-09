# frozen_string_literal: true

module Zr
  module Dev
    # Where a generator reads the C sources that zr's tables come from.
    # `RUBY_SRC` names a CRuby checkout that holds RUBY_REVISION, and
    # `PRISM_SRC` a prism checkout that holds the tag PRISM. Neither is
    # vendored: a table is written from them once and then committed.
    PRISM = "v1.9.0"

    # `RUBY_SRC`, else tmp/ruby.
    def self.ruby_src
      return File.expand_path(ENV["RUBY_SRC"]) unless ENV["RUBY_SRC"].to_s.empty?

      path("tmp/ruby")
    end

    # Whether a CRuby checkout is at hand.
    def self.ruby_src? = File.directory?(ruby_src)

    # `PRISM_SRC`, else a checkout in tmp/prism, else the release tree in
    # tmp/.
    def self.prism_src
      return File.expand_path(ENV["PRISM_SRC"]) if ENV["PRISM_SRC"]

      checkout = path("tmp/prism")
      tree = path("tmp/prism-#{PRISM.delete_prefix("v")}")
      File.directory?(checkout) || !File.directory?(tree) ? checkout : tree
    end

    # One CRuby source file at RUBY_REVISION.
    def self.cruby(path) = git_show(ruby_src, RUBY_REVISION, path, "RUBY_SRC")

    # The files below `dir` of CRuby at RUBY_REVISION.
    def self.cruby_files(dir)
      git("ls-tree", "--name-only", "#{RUBY_REVISION}:#{dir}", dir: ruby_src, err: $stderr).to_s.split("\n")
    end

    # One prism source file at PRISM: from a git checkout, or from a
    # release tree of that version (`tmp/prism-1.9.0`, which the prism
    # tests extract).
    def self.prism(path)
      return git_show(prism_src, PRISM, path, "PRISM_SRC") if File.exist?(File.join(prism_src, ".git"))

      tree = File.join(prism_src, path)
      return File.read(tree) if File.file?(tree)

      fail!("zr-dev: no #{path} in #{prism_src}; PRISM_SRC names a prism checkout or a #{PRISM} tree")
    end

    # Whether a prism source is at hand: a checkout, or a tree with its C
    # (a gem's release tree has none).
    def self.prism? = File.exist?(File.join(prism_src, ".git")) || File.directory?(File.join(prism_src, "src"))

    def self.git_show(checkout, revision, path, variable)
      unless File.directory?(checkout)
        url = variable == "RUBY_SRC" ? "https://github.com/ruby/ruby" : "https://github.com/ruby/prism"
        fail!("zr-dev: no checkout at #{checkout}. Run 'git clone #{url} #{checkout}', or set #{variable} to a checkout")
      end
      text = git("show", "#{revision}:#{path}", dir: checkout)
      return text if text

      fail!("zr-dev: no #{path} at #{revision[0, 12]} in #{checkout}; #{variable} names a checkout that has it")
    end
  end
end
