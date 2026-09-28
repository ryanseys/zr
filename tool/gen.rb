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
    # runs only under ruby 4.0.7 itself.
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
        "redefinitions" => ["runtime/core/redefinitions.rb: the core methods whose redefinition warns",
                            -> { require_relative "gen/redefinitions"; Redefinitions }],
        "unicode" => ["runtime/core/unicode.rb: the case mappings", -> { require_relative "gen/unicode"; Unicode }],
        "cjk" => ["runtime/core/cjk.rb: the multibyte code points", -> { require_relative "gen/cjk"; Cjk }],
        "enc_mb" => ["runtime/kernel/enc_mb.rb: the multibyte walkers", -> { require_relative "gen/enc_mb"; EncMb }],
        "onig_unicode" => ["runtime/core/regexp/unicode_tables.rb and runtime/kernel/onig_tables.rb: Onigmo's Unicode tables",
                          -> { require_relative "gen/onig_unicode"; OnigUnicode }],
        "onig_encodings" => ["runtime/core/regexp/onig/encoding_tables.rb: Onigmo's encodings past UTF-8",
                             -> { require_relative "gen/onig_encodings"; OnigEncodings }],
        "tables" => ["runtime/*/os/<os>/: this OS's errno, fcntl, etc and socket", -> { require_relative "gen/tables"; Tables }],
        "nkf" => ["runtime/ext/nkf/tables.rb: nkf's conversion tables", -> { require_relative "gen/nkf"; Nkf }],
        "openssl_constants" => ["runtime/ext/openssl/ossl/constants.rb: openssl's Integer constants",
                                -> { require_relative "gen/openssl_constants"; OpensslConstants }],
        "zlib_tables" => ["runtime/kernel/zlib_tables.rb: zlib's tables, computed as zlib's C computes them",
                          -> { require_relative "gen/zlib_tables"; ZlibTables }],
        "description" => ["runtime/ext/os/<os>/zr_description.rb: the kernel tables", -> { require_relative "gen/description"; Description }],
        "prism" => ["runtime/ext/prism/ruby/*.rb: the pure-Ruby prism", -> { require_relative "gen/prism"; PrismRuby }],
        "prism_encoding_tables" => ["runtime/ext/prism/ruby/encoding_tables.rb: prism's encodings",
                                    -> { require_relative "gen/prism_encoding_tables"; PrismEncodingTables }],
        "support" => ["docs/reference/support.md: what zr refuses, from the compiler", -> { require_relative "gen/support"; Support }],
        "perf" => ["docs/explanation/performance.md: the newest benchmark reports", -> { require_relative "gen/perf"; Perf }]
      })

      # Runs every generator. A generator that needs a checkout
      # (RUBY_SRC, PRISM_SRC) stops the run when the checkout is missing.
      # `openssl_constants` is not in the run: its order comes from the
      # host's OpenSSL build (see tool/gen/openssl_constants.rb), so run it
      # by name and read the diff.
      class All < Command
        APART = %w[all openssl_constants].freeze

        summary "Every generator, in order"
        usage "[--check]"

        def options(o) = o.on("--check", "write nothing; fail when a file is out of date") { @check = true }

        def run(_argv)
          words = Gen.commands.keys - APART
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
