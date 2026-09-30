# frozen_string_literal: true

module Zr
  module Dev
    # Where a generator reads the C sources that zr's tables come from.
    # `RUBY_SRC` names a CRuby checkout that holds RUBY_REVISION, and
    # `PRISM_SRC` a prism checkout that holds the tag PRISM. Neither is
    # vendored: a table is written from them once and then committed.
    PRISM = "v1.9.0"

    # `RUBY_SRC`, else ~/dev/github.com/ruby/ruby, else tmp/ruby.
    def self.ruby_src
      return File.expand_path(ENV["RUBY_SRC"]) unless ENV["RUBY_SRC"].to_s.empty?

      checkout = File.expand_path("~/dev/github.com/ruby/ruby")
      File.directory?(checkout) ? checkout : path("tmp/ruby")
    end

    # `PRISM_SRC`, else ~/dev/prism, else the release tree in tmp/.
    def self.prism_src
      return File.expand_path(ENV["PRISM_SRC"]) if ENV["PRISM_SRC"]

      checkout = File.expand_path("~/dev/prism")
      tree = path("tmp/prism-#{PRISM.delete_prefix("v")}")
      File.directory?(checkout) || !File.directory?(tree) ? checkout : tree
    end

    # One CRuby source file at RUBY_REVISION.
    def self.cruby(path) = git_show(ruby_src, RUBY_REVISION, path, "RUBY_SRC")

    # The files below `dir` of CRuby at RUBY_REVISION.
    def self.cruby_files(dir)
      IO.popen(["git", "-C", ruby_src, "ls-tree", "--name-only", "#{RUBY_REVISION}:#{dir}"], &:read).split("\n")
    end

    # One prism source file at PRISM: from a git checkout, or from a
    # release tree of that version (`tmp/prism-1.9.0`, which the prism
    # tests extract).
    def self.prism(path)
      return git_show(prism_src, PRISM, path, "PRISM_SRC") if File.exist?(File.join(prism_src, ".git"))

      tree = File.join(prism_src, path)
      return File.read(tree) if File.file?(tree)

      abort("zr-dev: no #{path} in #{prism_src}; PRISM_SRC names a prism checkout or a #{PRISM} tree")
    end

    # Whether a prism source is at hand.
    def self.prism? = File.directory?(prism_src)

    def self.git_show(checkout, revision, path, variable)
      unless File.directory?(checkout)
        url = variable == "RUBY_SRC" ? "https://github.com/ruby/ruby" : "https://github.com/ruby/prism"
        abort("zr-dev: no checkout at #{checkout}. Run 'git clone #{url} #{checkout}', or set #{variable} to a checkout")
      end
      text = IO.popen(["git", "-C", checkout, "show", "#{revision}:#{path}"], err: File::NULL, &:read)
      return text if $?.success?

      abort("zr-dev: no #{path} at #{revision[0, 12]} in #{checkout}; #{variable} names a checkout that has it")
    end
  end
end
