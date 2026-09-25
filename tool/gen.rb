# frozen_string_literal: true

require_relative "lib/zr/dev"

module Zr
  module Dev
    # `zr-dev gen <name>` writes one generated file again, and
    # `zr-dev gen all` writes every one. `--check` writes nothing and
    # fails when a file is out of date. Each generated file has a header
    # that names its generator; do not edit such a file by hand.
    #
    # A generator reads a reference: the running ruby, a CRuby source file
    # at RUBY_REVISION (`Dev.cruby`), prism's C (`Dev.prism`), or zr's own
    # runtime. A generator that reads the running ruby is `host_ruby!`: it
    # runs only under ruby 4.0.6 itself.
    class Gen < Group
      summary "Write a generated file again, or check it (--check)"

      commands({
        "all" => ["Every generator below, in order", -> { All }],
        "features" => ["lib/zr/hir/features.rb: the names require accepts", -> { require_relative "gen/features"; Features }],
        "libraries" => ["lib/zr/library_digests.rb: the pinned gems' digests", -> { require_relative "gen/libraries"; Libraries }],
        "libsystem" => ["lib/zr/obj/macho/libsystem.rb: the names libSystem defines", -> { require_relative "gen/libsystem"; Libsystem }],
        "encodings" => ["runtime/core/encodings.rb: the encodings ruby knows", -> { require_relative "gen/encodings"; Encodings }],
        "transcode" => ["runtime/core/transcode.rb: the single-byte tables", -> { require_relative "gen/transcode"; Transcode }],
        "emoji" => ["runtime/core/emoji.rb: the carriers' emoji", -> { require_relative "gen/emoji"; Emoji }],
        "builtin_lines" => ["runtime/core/builtin_lines.rb: CRuby's own Ruby methods", -> { require_relative "gen/builtin_lines"; BuiltinLines }],
        "unicode" => ["runtime/core/unicode.rb: the case mappings", -> { require_relative "gen/unicode"; Unicode }],
        "cjk" => ["runtime/core/cjk.rb: the multibyte code points", -> { require_relative "gen/cjk"; Cjk }],
        "enc_mb" => ["runtime/kernel/enc_mb.rb: the multibyte walkers", -> { require_relative "gen/enc_mb"; EncMb }],
        "tables" => ["runtime/*/os/<os>/: this OS's errno, fcntl, etc and socket", -> { require_relative "gen/tables"; Tables }],
        "description" => ["runtime/ext/os/<os>/zr_description.rb: the kernel tables", -> { require_relative "gen/description"; Description }],
        "prism" => ["runtime/ext/prism/ruby/*.rb: the pure-Ruby prism", -> { require_relative "gen/prism"; PrismRuby }],
        "prism_encoding_tables" => ["runtime/ext/prism/ruby/encoding_tables.rb: prism's encodings",
                                    -> { require_relative "gen/prism_encoding_tables"; PrismEncodingTables }]
      })

      # Runs every generator. A generator that needs a checkout
      # (RUBY_SRC, PRISM_SRC) stops the run when the checkout is missing.
      class All < Command
        summary "Every generator, in order"
        usage "[--check]"

        def options(o) = o.on("--check", "write nothing; fail when a file is out of date") { @check = true }

        def run(_argv)
          words = Gen.commands.keys - ["all"]
          failed = words.reject { |word| Gen.commands.fetch(word).last.call.new("gen #{word}").start(@check ? ["--check"] : []).zero? }
          failed.each { |word| warn "zr-dev gen all: #{word} failed" }
          failed.empty?
        end
      end
    end

    # One generated file. A subclass names the file with `writes`, and
    # prints it into `io` in `write(io)`.
    class Generator < Command
      class << self
        def writes(rel = nil)
          rel ? @writes = rel : @writes
        end
      end

      usage "[--check]"

      def options(o) = o.on("--check", "write nothing; fail when the file is out of date") { @check = true }

      def check? = @check || false

      def run(_argv)
        Dev.pinned!(name) if self.class.host_ruby?
        Dev.write(self.class.writes, check: check?) { |io| write(io) }
      end

      def write(_io) = raise(NotImplementedError, "#{self.class} writes nothing")
    end
  end
end
