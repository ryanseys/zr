# frozen_string_literal: true

require "digest/sha2"
require_relative "lib/zr/dev"

module Zr
  module Dev
    # The kernel's lowering on each target, as text that two runs can
    # compare: each function's IR fingerprint, the kernel's description,
    # each datum and the symbol names. The kernel's move to plain Ruby (A6)
    # changes its spelling and nothing else, so each step must keep this
    # the same.
    #
    #   zr-dev golden save [LABEL]    lower the kernel on each target, write tmp/golden/LABEL/
    #   zr-dev golden check [LABEL]   lower it again, and list what differs from LABEL
    #
    # LABEL is `base` when it is not given.
    class Golden < Command
      summary "Save or check the kernel's lowering on each target"
      usage "save|check [LABEL]"

      TARGETS = %w[aarch64-apple-darwin aarch64-linux-musl wasm32-wasi].freeze
      DIR = Dev.path("tmp/golden")

      def run(argv)
        require_relative "../lib/zr/runtime"
        verb, label = argv
        label ||= "base"
        case verb
        when "save" then save(label)
        when "check" then check(label)
        else fail!("give save or check")
        end
      end

      def save(label)
        dir = File.join(DIR, label)
        Paths.mkdir_p(dir)
        TARGETS.each do |triple|
          File.write(File.join(dir, "#{triple}.txt"), dump(Target.fetch(triple)))
          puts "saved #{triple}"
        end
      end

      def check(label)
        failed = TARGETS.reject do |triple|
          path = File.join(DIR, label, "#{triple}.txt")
          fail!("no golden #{Dev.rel(path)}; run `zr-dev golden save #{label}` first") unless File.file?(path)

          same?(triple, File.readlines(path, chomp: true), dump(Target.fetch(triple)).lines(chomp: true))
        end
        fail!("#{failed.join(", ")} differ from #{label}") unless failed.empty?
      end

      # Prints each line that differs, at most 20, and returns whether none does.
      def same?(triple, was, now)
        gone = was - now
        added = now - was
        if gone.empty? && added.empty?
          puts "#{triple}: the same (#{now.size} lines)"
          return true
        end
        puts "#{triple}: #{gone.size} lines gone, #{added.size} new"
        gone.first(10).each { |line| puts "  - #{line}" }
        added.first(10).each { |line| puts "  + #{line}" }
        false
      end

      # One line for each fact, sorted, so a reordered file changes nothing
      # that a build sees.
      def dump(target)
        sources = RuntimeSources.for(target).kernel_files.map { |path| [File.read(path), path] }
        unit = Machine::Lower.new(sources, Machine::Symbols.new).tap(&:run)
        defined = (unit.functions.map(&:name) + unit.data.map(&:name) + unit.raw).to_set
        lines = unit.functions.map { |f| "fn #{f.name} #{IR::Fingerprint.of(f, defined)}" }
        lines += unit.data.map do |d|
          bytes = d.section == :bss ? d.bytes.to_s : Digest::SHA256.hexdigest(d.bytes)
          relocs = d.relocs.map { |r| "#{r.offset}:#{r.kind}:#{r.symbol}:#{r.addend}" }.join(",")
          "data #{d.name} #{d.section} #{d.align} #{d.linkage} #{bytes} #{relocs}"
        end
        lines += unit.raw.map { |name| "raw #{name}" }
        lines += Machine::Description.of(unit).to_text.lines(chomp: true).map { |line| "desc #{line}" }
        lines += unit.symbols.names.each_with_index.map { |name, i| "sym #{i} #{name}" }
        "#{lines.sort.join("\n")}\n"
      end
    end
  end
end
