# frozen_string_literal: true

require "json"
require_relative "cli"
require_relative "gem_set"
require_relative "manifest"

module Zr
  # `zr gems`, `zr inspect` and `zr diff`: what a build reads, what a
  # binary was built with, and where a binary differs from ruby.
  module GemsCommand
    module_function

    # `zr gems [--gem ...] [--gemfile PATH] [--target TRIPLE] [--json] [FILE]`:
    # every gem that a build can read, or with FILE, the gems that FILE's
    # build reads.
    def gems(args)
      json = !args.delete("--json").nil?
      opts = CLI.parse("gems", args)
      gem_set = CLI.gem_set(opts)
      rows = if opts[:input]
               abort "zr: no such file: #{opts[:input]}" unless File.file?(opts[:input])
               of_file(opts[:input], gem_set, CLI.target_for(opts[:triple], opts[:emit], "gems"))
             else
               Manifest.all(gem_set)
             end
      json ? puts(JSON.generate(rows.map(&:to_h))) : print(table(rows))
    end

    # The gems that the build of `input` reads. A refused form stops as a
    # build does.
    def of_file(input, gem_set, target)
      require_relative "runtime"
      support = EvalSupport.for(target)
      hir = Hir.build(File.read(input), input, prebuilt: support, target: target, gem_set: gem_set)
      Manifest.of_program(hir, support, gem_set)
    rescue Refused => e
      warn CLI.refusal_report(e)
      exit CLI::REFUSED
    end

    # `zr inspect [--json] BINARY`: the gem manifest that a binary carries.
    def inspect(args)
      json = !args.delete("--json").nil?
      CLI.usage_error("unknown option '#{args.find { |a| a.start_with?("-") }}'", "inspect") if args.any? { |a| a.start_with?("-") }
      CLI.usage_error("give one binary", "inspect") unless args.size == 1
      path = args.first
      abort "zr: no such file: #{path}" unless File.file?(path)
      manifest = Manifest.find(File.binread(path))
      abort "zr: #{path} has no gem manifest; zr #{VERSION} did not build it" unless manifest
      return puts(JSON.generate(manifest)) if json

      puts "#{path}: zr #{manifest["zr"]}, ruby #{manifest["ruby"]}, #{manifest["target"]}"
      print table(manifest["gems"].map { |row| Manifest::Row.new(row["name"], row["version"], row["source"]) })
    end

    # A table: one row for each gem, and the version range of a port's C.
    def table(rows)
      return "no gems\n" if rows.empty?

      width = [rows.map { |row| row.name.size }.max, 4].max
      lines = rows.map do |row|
        port = Ports::ALL[row.name]
        note = port && row.source != "stdlib" ? "  C: zr's port, #{port.compat}" : ""
        format("%-#{width}s  %-10s %s%s", row.name, row.version, row.source, note).rstrip
      end
      "#{format("%-#{width}s  %-10s %s", "NAME", "VERSION", "SOURCE")}\n#{lines.join("\n")}\n"
    end

    # `zr diff [options] FILE [args...]`: runs FILE under ruby and as a zr
    # binary, and compares stdout, stderr, the exit status and the signal.
    # It prints the kind of difference (Diff.kind), and a diff of each
    # part. Exit status 0 when the two are the same, else 1.
    def diff(args)
      require_relative "diff"
      words = args.dup
      opts = CLI.parse("run", words)
      CLI.usage_error("--emit does not apply; zr diff runs a binary for this host", "diff") if opts[:emit]
      input = opts[:input]
      abort "zr: no such file: #{input}" unless File.file?(input)
      options = args.take(args.index(input))
      gem_set = CLI.gem_set(opts)
      Paths.tmpdir("zr-diff-") do |work|
        out = File.join(work, "program")
        built = Diff.run([RbConfig.ruby, File.join(Paths::ROOT, "exe/zr"), "build", *options, input, "-o", out], limit: nil)
        unless built.status.zero?
          puts built.status == CLI::REFUSED ? "refused" : "build-error"
          $stderr.print built.stderr
          exit 1
        end
        ruby = Diff.run([RbConfig.ruby, *ruby_flags(gem_set), input, *opts[:args]], env: ruby_env(opts))
        zr = Diff.run([out, *opts[:args]])
        kind = Diff.kind(ruby, zr)
        puts kind
        print Diff.report(ruby, zr)
        exit(kind == "same" ? 0 : 1)
      end
    end

    # ruby reads the same `--gem` roots that the build read.
    def ruby_flags(gem_set)
      gem_set.gems.reject(&:refusal).flat_map(&:roots).flat_map { |root| ["-I", root] }
    end

    # With a Gemfile, ruby runs as `bundle exec ruby` does.
    def ruby_env(opts)
      gemfile = opts[:gemfile] || ENV["BUNDLE_GEMFILE"]
      env = { "RUBYOPT" => nil, "BUNDLER_SETUP" => nil }
      return env if gemfile.to_s.empty?

      env.merge("BUNDLE_GEMFILE" => File.expand_path(gemfile), "RUBYOPT" => "-rbundler/setup")
    end
  end
end
