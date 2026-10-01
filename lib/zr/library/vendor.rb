# frozen_string_literal: true

module Zr
  module Library
    # What vendor/ holds, and the one file to edit to change it. vendor/ is
    # upstream code, byte for byte as its authors ship it. Nobody edits a
    # file there: `zr-dev vendor` writes the tree from these lists, from
    # lib/zr/library/ports.rb (the gems whose C zr ports, at zr's versions)
    # and from lib/zr/version.rb (the ruby release). It records every source
    # and every file's digest in vendor/vendor.lock.
    #
    # The tree is a ruby install prefix (Zr::Library::Layout), as a stock
    # ruby leaves it after `gem install` of the port gems:
    #
    #   vendor/ruby/lib/ruby/4.0.0/        ruby's own library and the default
    #                                      gems, from ruby's source at
    #                                      RUBY_REVISION
    #   vendor/ruby/lib/ruby/gems/4.0.0/   the bundled gems and the port
    #                                      gems, each from its .gem
    #   vendor/ruby/gem_prelude.rb         from ruby's source
    #   vendor/LICENSES/                   license texts that no gem
    #                                      directory holds
    #
    # zr's own code (lib/zr/runtime/) comes before this tree on the load path, so
    # a file there replaces an upstream file of the same name.
    # docs/how-to/update-vendored-code.md has the steps to add or update a
    # gem.
    module Vendor
      # The bundled gems of ruby that vendor/ holds, at the versions in
      # ruby's gems/bundled_gems. A bundled gem with a C part is a port
      # (lib/zr/library/ports.rb, at zr's version), or zr refuses it (rbs,
      # typeprof, debug, rdoc, repl_type_completor, win32ole).
      BUNDLED = %w[
        abbrev base64 benchmark csv drb getoptlong irb logger matrix minitest mutex_m net-ftp
        net-imap net-pop net-smtp observer ostruct power_assert prime pstore rake readline
        reline resolv-replace rexml rinda rss test-unit
      ].freeze

      # The parts of ruby's library that vendor/ leaves out, with the
      # reason. A name that ends in `/` is a directory.
      LEFT_OUT = {
        "prism.rb" => "the prism port gem replaces ruby's prism, and ruby's build writes part of it from templates",
        "prism/" => "the prism port gem replaces ruby's prism, and ruby's build writes part of it from templates",
        "win32/" => "only a Windows ruby installs it",
        "mkmf.rb" => "zr compiles no C, so it refuses mkmf (Hir::Build::UNSUPPORTED_LIBRARIES)",
        "bundler/man/index.txt" => "ruby's installer leaves it out"
      }.freeze

      # The default gems whose files LEFT_OUT removes: their specifications
      # stay out too.
      LEFT_OUT_GEMS = %w[prism].freeze

      # Files of a gem that vendor/ leaves out, with the reason.
      GEM_EXCLUDE = {
        "minitest" => { "lib/hoe/minitest.rb" => "a plugin of hoe, which ruby never loads from minitest" },
        "prism" => { "lib/prism/ffi.rb" => "prism's FFI half: zr refuses it (Hir::Build::UNSUPPORTED_LIBRARIES)" }
      }.freeze
    end
  end
end
