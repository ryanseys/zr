# frozen_string_literal: true

require "tmpdir"
require_relative "../spec"

module Zr
  module Dev
    class Specs
      # The parts of each example, as the reader gives them, and a digest
      # of them. `fingerprint` prints the digests; `verify` compares them
      # with a revision.
      module Parts
        module_function

        # Every example in a path, as `[file, name, digest, example, parts]`.
        #
        # `source` and the `files:` contents are compared as bytes. A
        # fixture in a file on disk has the ASCII-8BIT tag, but an inline
        # literal has UTF-8. Both zr and ruby write it with `File.binwrite`,
        # so no run can see the tag.
        #
        # `as:` is the correct location of the file. It is different from
        # the read location when an older revision is in a temporary file.
        # The default `path:` comes from the spec file's location. Without
        # `as:`, every example of the old revision would show a changed
        # path.
        def examples(path, renames: false, as: path)
          Dev.reader!
          Reader.read(path).map do |e|
            parts = { "describe" => e.about, "program" => e.source&.b,
                      "keywords" => bytes(e.given), "answer" => bytes(e.want) }
            unless renames
              written = e.given&.[](:path) || Reader.path_for(as)
              parts = { "sentence" => e.name, "path" => written }.merge(parts)
            end
            [Dev.rel(as), e.name, Digest::SHA256.hexdigest(Marshal.dump(parts.values)), e, parts]
          end
        end

        # The names of the parts of an example that differ, so that a report
        # tells which part changed.
        def moved(was, now) = was.keys.select { |k| was[k] != now[k] }

        # Changes each string in a hash or array to its bytes, so that a
        # comparison ignores the encoding tag.
        def bytes(value)
          case value
          when String then value.b
          when Hash then value.to_h { |k, v| [k, bytes(v)] }
          when Array then value.map { |v| bytes(v) }
          when Exception then [value.class.name, value.message]
          else value
          end
        end
      end

      class Fingerprint < Tool
        summary "A digest per example, to diff a rewrite against: zr-dev spec fingerprint > before.txt"

        def run(argv)
          n = 0
          files(argv).each do |file|
            Parts.examples(file).each do |f, name, digest, _|
              puts "#{digest}  #{f}  #{name}"
              n += 1
            end
          end
          warn "#{n} example(s) fingerprinted"
        end
      end

      class Verify < Tool
        summary "What moved since a revision; --renames allows new sentences"
        usage "[REVISION] [--renames] [path...]"

        def options(o) = o.on("--renames", "compare the examples without their sentences") { @renames = true }

        def run(argv)
          # The first word is a revision unless it names a path.
          rev = argv.first && !argv.first.start_with?("test/") ? argv.shift : "HEAD"
          apart = []
          checked = 0
          Dir.mktmpdir("zr-verify-") do |work|
            files(argv).each do |file|
              rel = Dev.rel(file)
              was = IO.popen(["git", "-C", ROOT, "show", "#{rev}:#{rel}"], err: File::NULL, &:read)
              next warn "#{rel}: not in #{rev}, skipped" unless $?.success?

              before = File.join(work, "before.rb")
              File.write(before, was)
              old = Parts.examples(before, renames: @renames, as: file)
              new = Parts.examples(file, renames: @renames)
              checked += new.size

              # Compare by position, not as a set. A set does not see a
              # change of order, and the position is the only stable key when
              # the sentences change.
              if old.size != new.size
                apart << "#{rel}: #{old.size} example(s) became #{new.size}"
                next
              end
              old.zip(new).each do |(_, was_name, was_digest, _, was_parts), (_, name, digest, e, parts)|
                apart << "#{rel}: #{name}: the example raised #{e.want[:error].class}" if e.want[:error]
                next if was_digest == digest

                apart << "#{rel}: #{was_name.inspect} -> #{name.inspect}: #{Parts.moved(was_parts, parts).join(", ")} changed"
              end
            end
          end
          apart.each { |line| warn line }
          puts format("%d example(s) checked against %s, %d apart", checked, rev, apart.size)
          apart.empty?
        end
      end
    end
  end
end
