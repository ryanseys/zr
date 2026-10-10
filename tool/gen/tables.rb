# frozen_string_literal: true

require_relative "../gen"

module Zr
  module Dev
    module Commands
      class Gen
        # `zr-dev gen tables` reads this OS's errno, fcntl, etc and socket tables from
        # the ruby that runs the task. It writes them into the OS layer for
        # that ruby's platform. The values are different on each platform
        # (O_NOCTTY is 0x20000 on darwin and 0x100 on Linux). Thus the task
        # reads them, as CRuby reads them from its headers.
        #
        # Each OS's own ruby writes its own layer (a darwin ruby here, an Alpine
        # ruby for linux, ruby.wasm under wasmtime for wasi). Thus no table
        # comes from the wrong OS. `--check` writes nothing and fails on a
        # changed table, as CI runs it.
        #
        #   zr-dev gen tables [--check]
        class Tables < Command
          host_ruby!
          usage "[--check]"

          def defaults = @check = false

          def options(o) = o.on("--check", "write nothing; fail when a table is out of date") { @check = true }

          def os = RUBY_PLATFORM[/darwin|linux|wasi/] || fail!("no OS layer for #{RUBY_PLATFORM}")

          def run(_argv)
            Dev.pinned!(name)
            @current = true
            errno
            fcntl
            etc
            socket
            @current
          end

          # Writes `text` to `lib/zr/runtime/<part>/os/<os>/<name>`, or with
          # --check compares it.
          def write(part, name, text)
            rel = File.join("lib/zr/runtime", part, "os", os, name)
            @current &= Dev.write(rel, check: @check) { |io| io.print text }
          end

          # The socket table reads ruby's list of names, which is in ruby's
          # source and not in an install. `MKCONSTANTS` names a copy of the file;
          # by default it comes from RUBY_SRC.
          def mkconstants
            path = ENV["MKCONSTANTS"]
            path ? File.read(path) : Dev.cruby("ext/socket/mkconstants.rb")
          end

          # The entries of a Hash literal, wrapped to the core's line width.
          def rows(items, indent)
            lines = [+""]
            items.each do |item|
              lines << +"" if lines.last.size + item.size + 2 > 100 - indent
              lines.last << (lines.last.empty? ? item : " #{item}")
              lines.last << ","
            end
            lines.last.chomp!(",")
            lines.map { |line| (" " * indent) + line }.join("\n")
          end

          # One entry for each Errno class, with its errno value. Other names of
          # a class become aliases (ruby gives all errnos that this platform does
          # not have one class, NOERROR). Signal.list is copied in ruby's order.
          def errno
            errno = Errno.constants.group_by { |name| Errno.const_get(name) }.map do |klass, names|
              primary = klass.name.delete_prefix("Errno::").to_sym
              [primary, klass::Errno, (names - [primary]).sort]
            end.sort_by { |name, code, _| [code, name] }

            codes = errno.map { |name, code, _| "#{name}: #{code}" }
            aliases = errno.flat_map { |name, _, others| others.map { |other| "#{other}: :#{name}" } }
            signals = Signal.list.map { |name, number| "#{name.inspect} => #{number}" }

            write("core", "errno.rb", <<~RUBY)
              # frozen_string_literal: true

              # Written by `zr-dev gen tables` from ruby #{RUBY_VERSION} on #{RUBY_PLATFORM}; do not edit.
              # Every Errno name and the errno it stands for, one row per class; a
              # name in ALIASES is another name for a class in CODES. Signal::LIST is
              # Signal.list in ruby's order.
              module Errno
                CODES = {
              #{rows(codes, 4)}
                }.freeze
                ALIASES = {
              #{rows(aliases, 4)}
                }.freeze
                private_constant :CODES, :ALIASES
              end

              module Signal
                LIST = {
              #{rows(signals, 4)}
                }.freeze
                private_constant :LIST
              end
            RUBY
          end

          # The output includes only the names that the platform has.
          FCNTL_GROUPS = {
            "The fcntl(2) commands, of which POSIX numbers the first five." =>
              %w[F_DUPFD F_GETFD F_SETFD F_GETFL F_SETFL F_GETLK F_SETLK F_SETLKW],
            "The one flag F_SETFD carries." => %w[FD_CLOEXEC],
            "The kinds of lock a lock command asks for." => %w[F_RDLCK F_WRLCK F_UNLCK],
            "The access modes of open(2), and the mask that reads them back." =>
              %w[O_RDONLY O_WRONLY O_RDWR O_ACCMODE],
            "The status flags, each a bit of its own. O_NDELAY is the older " \
            "spelling of O_NONBLOCK and names the same bit." =>
              %w[O_APPEND O_CREAT O_EXCL O_TRUNC O_NONBLOCK O_NDELAY O_NOCTTY]
          }.freeze

          def fcntl
            require "fcntl"
            named = FCNTL_GROUPS.values.flatten + ["VERSION"]
            rest = Fcntl.constants.map(&:to_s).sort - named

            out = +"# frozen_string_literal: true\n\n"
            out << "# `require \"fcntl\"`: the names of the fcntl(2) commands and the flags\n"
            out << "# they carry. The module is a table and nothing else; the calls that use\n"
            out << "# it are IO's own. Generated by `zr-dev gen tables` from ruby's Fcntl.\n"
            out << "module Fcntl\n"
            out << "  VERSION = #{Fcntl::VERSION.inspect}\n"
            FCNTL_GROUPS.each do |note, names|
              names = names.select { |name| Fcntl.const_defined?(name) }
              next if names.empty?

              out << "\n"
              note.scan(/.{1,68}(?:\s|\z)/) { |line| out << "  # #{line.strip}\n" }
              names.each { |name| out << "  #{name} = #{Fcntl.const_get(name)}\n" }
            end
            unless rest.empty?
              out << "\n  # What this platform adds of its own.\n"
              rest.each { |name| out << "  #{name} = #{Fcntl.const_get(name)}\n" }
            end
            out << "end\n"
            write("ext", "fcntl.rb", out)
          end

          # The sysconf, confstr and pathconf names that Etc defines, and the
          # members of Etc::Passwd and Etc::Group. The members are the fields of
          # this OS's struct passwd and struct group. An OS with no group
          # database has no Etc::Group.
          def etc
            require "etc"
            rows = Etc.constants.sort.filter_map do |name|
              value = Etc.const_get(name)
              [name, value] if value.is_a?(Integer)
            end

            out = +"# frozen_string_literal: true\n\n# Generated by `zr-dev gen tables` from ruby's own etc. Do not edit.\nmodule Etc\n"
            rows.each { |name, value| out << "  #{name} = #{value}\n" }
            structs = { "PASSWD_MEMBERS" => :Passwd, "GROUP_MEMBERS" => :Group }
                      .select { |_, name| Etc.const_defined?(name, false) }
            out << "\n"
            structs.each { |constant, name| out << "  #{constant} = %i[#{Etc.const_get(name).members.join(" ")}].freeze\n" }
            out << "  private_constant #{structs.keys.map { |constant| ":#{constant}" }.join(", ")}\n"
            out << "end\n"
            write("ext", "etc_names.rb", out)
          end

          # The constants that socket defines, in the order that
          # ext/socket/mkconstants.rb lists them. When several names have the
          # same number, this order sets which name is shown.
          def socket
            require "socket"
            listed = mkconstants.split(/^__END__\n/).last.each_line.filter_map do |line|
              name = line.split.first
              name.to_sym unless name.nil? || name.start_with?("#")
            end
            names = listed.uniq.select { |name| Socket::Constants.const_defined?(name, false) }

            out = +<<~HEAD
              # frozen_string_literal: true

              # Generated by `zr-dev gen tables` from ruby's own socket, in the order
              # ext/socket/mkconstants.rb lists the names. Do not edit.
              class Socket < BasicSocket
                module Constants
            HEAD
            names.each { |name| out << "    #{name} = #{Socket::Constants.const_get(name)}\n" }
            out << "  end\n\n"
            out << "  # Every name above, in that order.\n"
            out << "  def self.constant_names\n"
            out << "    Primitive.attr! :hidden\n"
            out << "    %i[\n"
            names.each_slice(8) { |slice| out << "      #{slice.join(" ")}\n" }
            out << "    ]\n"
            out << "  end\n"
            out << "end\n"
            write("ext", "socket/constants.rb", out)
          end
        end
      end
    end
  end
end
