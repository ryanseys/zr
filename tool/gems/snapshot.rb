# frozen_string_literal: true

require_relative "../lib/zr/dev/gems"

module Zr
  module Dev
    class GemCompat
      # `zr-dev gems snapshot [REVISION]`: a copy of zr at a commit (HEAD
      # by default) in tmp/gems/zr/<commit>, with its compiled compiler
      # built. A sweep with `--zr DIR` then builds with the copy, so zr
      # can change in this checkout while the sweep runs:
      #
      #   dir=$(zr-dev gems snapshot)
      #   zr-dev gems sweep --zr "$dir" --top 200 --save
      #
      # `--list` prints the copies, and `--remove DIR` removes one.
      class Snapshot < Base
        summary "A copy of zr at a commit, for a sweep that runs while zr changes"
        usage "[REVISION] [--list] [--remove DIR]"

        def defaults
          super
          @list = false
          @remove = nil
        end

        def options(o)
          o.on("--list", "print the copies") { @list = true }
          o.on("--remove DIR", "remove the copy at DIR") { |v| @remove = v }
        end

        def run(argv)
          fail!("give at most one revision") if argv.size > 1
          return list if @list
          return remove(@remove) if @remove

          snapshot = Gems::Snapshot.make(argv.first || "HEAD")
          warn "zr-dev #{name}: building the compiled compiler of #{snapshot.commit}; the first one takes some minutes"
          fail!("the compiled compiler of #{snapshot.root} did not build") unless snapshot.warm!
          puts snapshot.root
          true
        rescue Gems::Failure => e
          fail!(e.message)
        end

        def list
          dirs = File.directory?(Gems::Snapshot::DIR) ? Dir.children(Gems::Snapshot::DIR).sort : []
          dirs.each { |dir| puts File.join(Gems::Snapshot::DIR, dir) }
        end

        # `git worktree remove`: git forgets the copy, and its directory
        # with its cache goes.
        def remove(dir)
          root = File.expand_path(dir)
          fail!("#{dir} is not a copy in #{Dev.rel(Gems::Snapshot::DIR)}") unless File.dirname(root) == Gems::Snapshot::DIR
          Dev.git("worktree", "remove", "--force", root) or fail!("git worktree remove #{root} failed")
          puts "removed #{Dev.rel(root)}"
        end
      end
    end
  end
end
