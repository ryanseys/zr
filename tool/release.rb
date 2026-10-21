# frozen_string_literal: true

require "json"
require "open3"
require_relative "lib/zr/dev"
require_relative "bump"
require_relative "../.github/scripts/ci_passed"

module Zr
  module Dev
    module Commands
      # `zr-dev release X.Y.Z` does the steps of docs/how-to/release.md up
      # to the tag: the bump commit (`zr-dev bump`), its push, the wait for
      # a CI run that passed for it, a look at the prerelease of that
      # commit, and then the tag and its push. The tag push starts the
      # release workflow. A person approves the `release` environment there.
      #
      # The decisions are class methods that read texts only, so a test
      # runs them with no GitHub and no git.
      class Release < Command
        summary "Make a release up to the tag: bump, push, wait for CI, check the prerelease, tag, push the tag"
        usage "X.Y.Z [--date YYYY-MM-DD] [--wait MINUTES] [--yes] [--dry-run]"

        SLUG = Bump::REPO.delete_prefix("https://github.com/")
        POLL = 30
        # The files that `zr-dev bump` can change.
        BUMPED = %w[lib/zr/version.rb Gemfile.lock README.md CHANGELOG.md].freeze

        def defaults
          @date = nil
          @wait = 90
          @yes = false
          @dry = false
        end

        def options(o)
          o.on("--date DATE", "the date of the release (default today)") { |date| @date = date }
          o.on("--wait MINUTES", Integer, "stop waiting for CI after this long (default 90)") { |minutes| @wait = minutes }
          o.on("--yes", "do not ask before the tag") { @yes = true }
          o.on("--dry-run", "change nothing; print what each step would do") { @dry = true }
        end

        def run(argv)
          version = argv.fetch(0) { fail!("give a version, X.Y.Z") }
          fail!("#{version} is not X.Y.Z") unless version.match?(/\A\d+\.\d+\.\d+\z/)
          check_start(version)
          sha = bump(version)
          return if sha.nil?

          return unless wait_for_ci(sha)

          check_prerelease(version, sha)
          return puts("dry run: would ask, tag v#{version} at #{sha[0, 7]} and push the tag") if @dry
          return puts("Nothing changed: v#{version} has no tag.") unless confirm?("Tag v#{version} at #{sha[0, 7]} and push it?")

          tag(version, sha)
        end

        # Whether the bump of `version` is on the branch already: the
        # changelog has its dated section and version.rb names it.
        def self.already_bumped?(changelog, version_rb, version)
          Bump.versions(changelog).include?(version) && version_rb.match?(/^  VERSION = "#{Regexp.escape(version)}"$/)
        end

        # The part of a release's `body` that names the targets that the
        # release leaves out, or nil. It is the line "Not in this release"
        # and the list under it.
        def self.left_out(body)
          lines = body.to_s.lines.map(&:chomp)
          start = lines.index { it.start_with?("Not in this release") } or return
          rest = lines.drop(start + 1).take_while { it.empty? || it.start_with?("- ") }
          [lines[start], *rest].join("\n").strip
        end

        # Where the CI of a commit stands, from its workflow `runs` (the
        # API's) as [state, run]. The state is :passed when a run has a
        # release job that passed (the block gets a run's id and gives its
        # jobs), :failed when every run that counts has ended and none
        # passed, and :waiting when a run is still going or none exists.
        # The run is the one that passed, or the newest one.
        def self.ci_state(runs)
          runs = CIGate.candidates(runs)
          passed = runs.find { |run| CIGate.ok?(yield(run["id"])) }
          return [:passed, passed] if passed
          return [:failed, runs.first] if runs.any? && runs.all? { it["status"] == "completed" }

          [:waiting, runs.first]
        end

        # The tag of the prerelease that CI makes for the commit `sha`.
        def self.prerelease_tag(version, sha) = "v#{version}.g#{sha[0, 7]}"

        private

        # Step 1: the preconditions. A dry run says which would stop a real
        # run, and goes on.
        def check_start(version)
          problems(version).each { |text| @dry ? puts("dry run: would stop: #{text}") : fail!(text) }
        end

        def problems(version)
          tag = "v#{version}"
          found = []
          found << "gh is not installed or not logged in; run `gh auth login`" unless gh_ready?
          branch = git("branch", "--show-current").strip
          found << "the branch is #{branch.inspect}, not main" unless branch == "main"
          found << "the working tree has changes; commit or stash them" unless git("status", "--porcelain").empty?
          git!("fetch", "origin", "main", "--tags")
          found << "HEAD is not origin/main; pull or push first" unless git("rev-parse", "HEAD").strip == git("rev-parse", "origin/main").strip
          found << "the tag #{tag} exists here" if git_ok?("rev-parse", "-q", "--verify", "refs/tags/#{tag}")
          found << "the tag #{tag} exists on origin" unless git!("ls-remote", "--tags", "origin", "refs/tags/#{tag}").strip.empty?
          found
        end

        # Step 2: the bump commit and its push. Returns the SHA of the
        # commit that CI checks, or nil when a dry run has no such commit.
        def bump(version)
          changelog = File.read(Dev.path("CHANGELOG.md"))
          if Release.already_bumped?(changelog, File.read(Dev.path("lib/zr/version.rb")), version)
            puts "The bump of #{version} is made already; using HEAD."
            return git!("rev-parse", "HEAD").strip
          end

          args = [version, *date_option]
          args << "--dry-run" if @dry
          fail!("zr-dev bump failed") unless Bump.new("bump").start(args).zero?
          return puts("dry run: would commit the files above as \"release: #{version}\", push main, and wait for CI") if @dry

          commit(version)
        end

        def date_option = @date ? ["--date", @date] : []

        def commit(version)
          changed = git!("status", "--porcelain").lines.map { it[3..].strip } & BUMPED
          fail!("the bump changed none of #{BUMPED.join(", ")}") if changed.empty?
          git!("add", *changed)
          puts git!("diff", "--cached", "--stat")
          git!("commit", "-m", "release: #{version}")
          git!("push", "origin", "main")
          git!("rev-parse", "HEAD").strip
        end

        # Step 3: waits until a CI run of `sha` has a release job that
        # passed, and returns true. A dry run reports the state once, and
        # returns false when CI has not passed.
        def wait_for_ci(sha)
          deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + (@wait * 60)
          loop do
            runs = gh_json("api", "repos/#{SLUG}/actions/workflows/ci.yml/runs?head_sha=#{sha}&per_page=100").fetch("workflow_runs")
            state, run = Release.ci_state(runs) { |id| jobs_of(id) }
            where = run ? " (#{run["html_url"]})" : ""
            case state
            when :passed
              puts "CI passed for #{sha[0, 7]}#{where}"
              return true
            when :failed then fail!("no CI run of #{sha[0, 7]} has a release job that passed#{where}")
            end
            if @dry
              puts "dry run: CI has not passed for #{sha[0, 7]} yet#{where}; a real run would wait"
              return false
            end

            fail!("CI did not pass for #{sha[0, 7]} in #{@wait} minutes#{where}") if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
            puts "Waiting for CI of #{sha[0, 7]}: #{runs.size} runs#{where}"
            sleep POLL
          end
        end

        def jobs_of(id) = gh_json("api", "repos/#{SLUG}/actions/runs/#{id}/jobs?filter=latest&per_page=100").fetch("jobs")

        # Step 4: the prerelease that CI made for the commit.
        def check_prerelease(version, sha)
          tag = Release.prerelease_tag(version, sha)
          release = gh_json("release", "view", tag, "--json", "body,assets", missing: "no prerelease #{tag}; CI makes it when the release job passes")
          puts "Prerelease #{tag} has:", *release.fetch("assets").map { "  #{it["name"]}" }
          left = Release.left_out(release["body"])
          warn "Warning: #{left}" if left
        end

        def confirm?(question)
          return true if @yes

          print "#{question} [y/N] "
          $stdin.gets.to_s.strip.match?(/\Ay(es)?\z/i)
        end

        # Step 6: the tag and its push.
        def tag(version, sha)
          git!("tag", "v#{version}", sha)
          git!("push", "origin", "v#{version}")
          puts "Pushed v#{version}. The release workflow starts now.",
               "Approve the `release` environment deployment there:",
               "https://github.com/#{SLUG}/actions/workflows/release.yml"
        end

        # The commands below are the only ones that touch git and GitHub.
        # Each takes an argument list, never a shell string.
        def gh_ready? = capture("gh", "auth", "status")[1]

        def git(*args) = capture("git", *args).first

        def git_ok?(*args) = capture("git", *args)[1]

        def git!(*args)
          out, ok, err = capture("git", *args)
          ok ? out : fail!("git #{args.join(" ")} failed: #{err.strip}")
        end

        def gh_json(*args, missing: nil)
          out, ok, err = capture("gh", *args)
          ok ? JSON.parse(out) : fail!(missing || "gh #{args.first(2).join(" ")} failed: #{err.strip}")
        end

        # [stdout, success, stderr] of a child in the checkout.
        def capture(*argv)
          out, err, status = Open3.capture3(*argv, chdir: Dev::ROOT)
          [out, status.success?, err]
        rescue SystemCallError => e
          ["", false, e.message]
        end
      end
    end
  end
end
