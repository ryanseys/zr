# frozen_string_literal: true

require "time"
require_relative "../gen"

module Zr
  module Dev
    module Commands
      class Gen
        # Writes what zr knows of the ruby that `.ruby-version` pins: the
        # record that the compiler, the gem and the tools read
        # (lib/zr/ruby_version.rb), and the constants that a program sees
        # (lib/zr/runtime/core/ruby_version.rb). Both come from ruby's own
        # sources at that version (RUBY_SRC), as ruby's build gives them,
        # never from the ruby that runs the generator.
        #
        # A new ruby is one edit: write its name into `.ruby-version`, check
        # out its tag in RUBY_SRC, run this generator, then `zr-dev vendor`
        # and the other generators (`zr-dev gen all`).
        class RubyVersion < Command
          RECORD = "lib/zr/ruby_version.rb"
          RUNTIME = "lib/zr/runtime/core/ruby_version.rb"

          # The facts of one ruby, as its sources give them.
          Facts = Data.define(:pin, :version, :patchlevel, :release_date, :revision, :copyright, :description_head, :api,
                              :lib_version)

          summary "lib/zr/ruby_version.rb and lib/zr/runtime/core/ruby_version.rb: the ruby that .ruby-version pins"
          usage "[--check]"

          def defaults = @check = false

          def options(o) = o.on("--check", "write nothing; fail when a file is out of date") { @check = true }

          def run(_argv)
            facts = read_facts(File.read(Dev.path(".ruby-version")).strip, Dev.ruby_src)
            [[RECORD, self.class.record_text(facts)], [RUNTIME, self.class.runtime_text(facts)]].map do |rel, text|
              Dev.write(rel, check: @check) { |io| io.print(text) }
            end.all?
          end

          # The facts of the pinned ruby from its checkout `src`: from its
          # tag when the checkout has tags, else from the commit that the
          # checkout is at (HEAD), or that it fetched last (FETCH_HEAD, as CI
          # fetches one revision). That commit must be of the pinned version.
          def read_facts(pin, src)
            head = ["refs/tags/v#{pin}", "HEAD", "FETCH_HEAD"].lazy.filter_map do |ref|
              Dev.git("rev-parse", "--verify", "--quiet", "#{ref}^{commit}", dir: src)&.strip
            end.first or fail!("RUBY_SRC (#{src}) is not a git checkout of ruby; clone its tag v#{pin} there")

            # A release is X.Y.Z; a preview or a release candidate is
            # X.Y.Z-previewN or -rcN, whose tarball's version.h names its stage
            # ("X.Y.ZpreviewN"), as tool/make-snapshot writes it.
            release = pin.match(/\A(\d+\.\d+\.\d+)(?:-((?:preview|rc)\d+))?\z/) or
              fail!(".ruby-version names #{pin}; zr takes a ruby release (X.Y.Z) or a preview (X.Y.Z-previewN)")
            named, label = release.captures
            version_h = Dev.git_show(src, head, "version.h", "RUBY_SRC")
            api_h = Dev.git_show(src, head, "include/ruby/version.h", "RUBY_SRC")
            api = "#{define(api_h, "RUBY_API_VERSION_MAJOR")}.#{define(api_h, "RUBY_API_VERSION_MINOR")}"
            version = "#{api}.#{define(version_h, "RUBY_VERSION_TEENY")}"
            patchlevel = Integer(define(version_h, "RUBY_PATCHLEVEL"))
            # A preview is a development build: patchlevel -1, and its
            # RUBY_ABI_VERSION suffixes the library directories
            # (RUBY_LIB_VERSION_STYLE 3, "full": X.Y.Z+ABI).
            dev = patchlevel == -1
            unless version == named && dev == !label.nil?
              fail!(".ruby-version names ruby #{pin}, and RUBY_SRC (#{src}) is ruby #{version}#{"-dev" if dev}; check out v#{pin} there")
            end
            abi = "+#{define(Dev.git_show(src, head, "include/ruby/internal/abi.h", "RUBY_SRC"), "RUBY_ABI_VERSION")}" if dev

            # tool/lib/vcs.rb dates a build by its commit, in Japan's time.
            committed = Time.iso8601(Dev.git("log", "-1", "--format=%cI", head, dir: src).to_s.strip)
            date = committed.getlocal("+09:00").strftime("%Y-%m-%d")
            author = api_h[/^#\s*define RUBY_AUTHOR "([^"]*)"/, 1] or fail!("ruby's sources define no RUBY_AUTHOR")
            # version.c's ruby_description, with the " +PRISM" that ruby adds
            # when prism parses, as it always does in zr. A development build
            # names its branch, master unless its revision.h says another; a
            # release says "revision".
            branch = dev ? "master" : "revision"
            Facts.new(pin: pin, version: version, patchlevel: patchlevel, release_date: date, revision: head,
                      copyright: "ruby - Copyright (C) #{define(api_h, "RUBY_BIRTH_YEAR")}-#{date[0, 4]} #{author}",
                      description_head: "ruby #{version}#{label} (#{date} #{branch} #{head[0, 10]}) +PRISM",
                      api: api, lib_version: "#{api}.#{define(api_h, "RUBY_API_VERSION_TEENY")}#{abi}")
          end

          # The value of a `#define NAME value` line of a C header.
          def define(header, name) = header[/^#\s*define #{name}\s+(\S+)/, 1] || fail!("ruby's sources define no #{name}")

          # The text of lib/zr/ruby_version.rb.
          def self.record_text(facts)
            <<~RUBY
              # frozen_string_literal: true

              # Generated by `zr-dev gen ruby_version` from `.ruby-version` and ruby's
              # sources at that version. Do not edit: write another version into
              # `.ruby-version` and run the generator again.
              #
              # Inside `module Zr` these names are the pinned ruby's, not the host's:
              # `::RUBY_REVISION` is the host's.
              module Zr
                # The ruby that zr runs on and matches, as `.ruby-version` names it.
                RUBY_PIN = #{facts.pin.inspect}
                # Its RUBY_VERSION, RUBY_PATCHLEVEL, RUBY_RELEASE_DATE, RUBY_REVISION
                # and RUBY_COPYRIGHT.
                RUBY = #{facts.version.inspect}
                RUBY_PATCHLEVEL = #{facts.patchlevel}
                RUBY_RELEASE_DATE = #{facts.release_date.inspect}
                RUBY_REVISION = #{facts.revision.inspect}
                RUBY_COPYRIGHT = #{facts.copyright.inspect}
                # Its RUBY_DESCRIPTION, without the " [platform]" at the end.
                RUBY_DESCRIPTION_HEAD = #{facts.description_head.inspect}
                # Its API version, which C extensions are built for, and the name of
                # its library directories (RbConfig's `ruby_version`).
                RUBY_API = #{facts.api.inspect}
                RUBY_LIB_VERSION = #{facts.lib_version.inspect}
              end
            RUBY
          end

          # The text of lib/zr/runtime/core/ruby_version.rb: the constants
          # that ruby defines at boot, in its order, and the name of the
          # library directories, which core/env.rb, core/kernel.rb and
          # ext/rbconfig.rb read.
          def self.runtime_text(facts)
            <<~RUBY
              # frozen_string_literal: true

              # Generated by `zr-dev gen ruby_version` from `.ruby-version` and ruby's
              # sources at that version. Do not edit.
              #
              # The constants that describe the ruby that the program runs as.
              RUBY_VERSION = #{facts.version.inspect}
              RUBY_ENGINE = "ruby"
              RUBY_ENGINE_VERSION = #{facts.version.inspect}
              RUBY_PLATFORM = Primitive.zr_os_ruby_platform.freeze
              RUBY_PATCHLEVEL = #{facts.patchlevel}
              RUBY_RELEASE_DATE = #{facts.release_date.inspect}
              RUBY_REVISION = #{facts.revision.inspect}
              RUBY_COPYRIGHT = #{facts.copyright.inspect}
              RUBY_DESCRIPTION = "#{facts.description_head} [\#{RUBY_PLATFORM}]".freeze
              # RbConfig's `ruby_version`: the name of the library directories.
              Primitive.zr_hidden_set(Kernel, :__zr_ruby_lib_version__, #{facts.lib_version.inspect})
            RUBY
          end

          # The facts that lib/zr/ruby_version.rb holds, for the checks that
          # the other files agree with it.
          def self.recorded
            Facts.new(pin: RUBY_PIN, version: RUBY, patchlevel: RUBY_PATCHLEVEL, release_date: RUBY_RELEASE_DATE,
                      revision: RUBY_REVISION, copyright: RUBY_COPYRIGHT, description_head: RUBY_DESCRIPTION_HEAD,
                      api: RUBY_API, lib_version: RUBY_LIB_VERSION)
          end
        end
      end
    end
  end
end
