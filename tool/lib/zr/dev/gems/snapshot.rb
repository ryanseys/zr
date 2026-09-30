# frozen_string_literal: true

module Zr
  module Dev
    module Gems
      # A copy of zr at one commit, in tmp/gems/zr/<commit>: a git
      # worktree with its own cache (tmp/cache below it), its own runtime
      # and its own compiled compiler. A long sweep builds with the copy,
      # so a change to zr in the checkout does not stop its builds
      # (Zr::SourceChanged), and each row names the zr that made it.
      class Snapshot
        DIR = File.join(TMP, "zr")

        attr_reader :root

        # The copy of `revision` (a commit, a branch or HEAD), made when
        # it is not there yet. Only committed work is in the copy.
        def self.make(revision = "HEAD")
          commit = git(Dev::ROOT, "rev-parse", "--short=12", "#{revision}^{commit}") or raise Failure.new("snapshot", "no commit #{revision}")
          root = File.join(DIR, commit)
          unless File.exist?(File.join(root, "exe/zr"))
            FileUtils.mkdir_p(DIR)
            git(Dev::ROOT, "worktree", "add", "--detach", root, commit) or raise Failure.new("snapshot", "git worktree add #{root} failed")
          end
          new(root)
        end

        # An existing copy (or any zr checkout) at `root`.
        def initialize(root)
          @root = File.expand_path(root)
          raise ArgumentError, "#{@root}: no exe/zr; `zr-dev gems snapshot` makes a copy" unless File.file?(File.join(@root, "exe/zr"))
        end

        def zr = File.join(@root, "exe/zr")

        def commit = Snapshot.git(@root, "rev-parse", "--short=12", "HEAD").to_s

        # Builds the copy's compiled compiler, and so its runtime, as
        # `rake build:self` does. A build then takes seconds, not minutes.
        # Returns true when it is current.
        def warm!
          script = "require #{File.join(@root, "lib/zr/bootstrap/handoff").dump}; Zr::Bootstrap::Handoff.build; exit Zr::Bootstrap::Handoff.current?"
          system({ "BUNDLE_GEMFILE" => nil, "RUBYOPT" => nil }, Dev.ruby, "-e", script, chdir: @root)
        end

        # The output of a git command in `dir`, or nil when it fails.
        def self.git(dir, *args)
          out = IO.popen(["git", "-C", dir, *args], err: File::NULL, &:read).strip
          $?.success? ? out : nil
        end
      end
    end
  end
end
