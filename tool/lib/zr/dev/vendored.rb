# frozen_string_literal: true

module Zr
  module Dev
    # What vendor/ holds, and the one file to edit to change it. vendor/ is
    # upstream code, byte for byte as its authors ship it. Nobody edits a
    # file there: `zr-dev vendor` writes the tree from these lists, from
    # lib/zr/library/ports.rb (the gems whose C zr ports, at zr's versions)
    # and from lib/zr/ruby_version.rb (the ruby release). It records every source
    # and every file's digest in vendor/vendor.lock.
    #
    # The tree is a ruby install prefix (Zr::Library::Layout), as a stock
    # ruby leaves it after `gem install` of the port gems:
    #
    #   vendor/ruby/lib/ruby/<API>/        ruby's own library and the default
    #                                      gems, from ruby's source at
    #                                      RUBY_REVISION
    #   vendor/ruby/lib/ruby/gems/<API>/   the bundled gems and the port
    #                                      gems, each from its .gem
    #   vendor/ruby/gem_prelude.rb         from ruby's source
    #   vendor/LICENSES/                   license texts that no gem
    #                                      directory holds
    #
    # zr's own code (lib/zr/runtime/) comes before this tree on the load path, so
    # a file there replaces an upstream file of the same name.
    # docs/how-to/update-vendored-code.md has the steps to add or update a
    # gem.
    module Vendored
      # The bundled gems of ruby that vendor/ holds, at the versions in
      # ruby's gems/bundled_gems. A bundled gem with a C part is a port
      # (lib/zr/library/ports.rb, at zr's version), or zr refuses it (rbs,
      # typeprof, debug, rdoc, repl_type_completor), or only a Windows ruby
      # installs it (win32ole, win32-registry).
      BUNDLED = %w[
        abbrev base64 benchmark csv drb getoptlong irb logger matrix minitest mutex_m net-imap
        net-smtp observer ostruct power_assert prime pstore rake readline reline resolv-replace
        rexml rinda rss test-unit tsort
      ].freeze

      # The parts of ruby's library that vendor/ leaves out, with the
      # reason. A name that ends in `/` is a directory.
      LEFT_OUT = {
        "ruby/prism/ffi.rb" => "Ruby::Prism's FFI half: zr refuses it (Hir::Build::UNSUPPORTED_LIBRARIES)",
        "win32/" => "only a Windows ruby installs it",
        "mkmf.rb" => "zr runs mkmf in the host ruby, never in a program (Hir::Build::UNSUPPORTED_LIBRARIES)",
        "mkmf/" => "zr refuses mkmf (Hir::Build::UNSUPPORTED_LIBRARIES)",
        "json.rb" => "the json port gem comes first on every load path (Ports.roots), so ruby's own copy is never read",
        "json/" => "the json port gem comes first on every load path (Ports.roots), so ruby's own copy is never read",
        "bundler/man/index.txt" => "ruby's installer leaves it out"
      }.freeze

      # Files of a gem that vendor/ leaves out, with the reason.
      GEM_EXCLUDE = {
        "minitest" => { "lib/hoe/minitest.rb" => "a plugin of hoe, which ruby never loads from minitest" },
        "prism" => { "lib/prism/ffi.rb" => "prism's FFI half: zr refuses it (Hir::Build::UNSUPPORTED_LIBRARIES)" }
      }.freeze

      # For each target other than this host, how to build the pinned ruby
      # for it: the image that builds it (pinned by digest), its platform,
      # and the packages that its configure finds. `zr-dev vendor` builds
      # the release tarball there (ruby-lang.org's releases.yml gives its
      # URL and SHA-256) as the official ruby image does, and its headers
      # and rbconfig.rb go into Layout.target_root. A C extension for that
      # target compiles against them (`Ext::Builder`, mkmf's
      # --target-rbconfig). Its config.h is what ruby's configure wrote
      # there, which no source has.
      TARGET_RUBIES = {
        "aarch64-linux-musl" => {
          image: "docker.io/library/alpine@sha256:294b683cb724975bec92580e1e685676bd4b50bda910ddb8c51d4cabeaec77e6",
          platform: %w[linux arm64],
          packages: %w[build-base bzip2-dev gdbm-dev gmp-dev libffi-dev linux-headers ncurses-dev openssl-dev
                       readline-dev yaml-dev zlib-dev]
        }
      }.freeze
    end
  end
end
