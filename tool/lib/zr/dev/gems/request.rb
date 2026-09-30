# frozen_string_literal: true

module Zr
  module Dev
    module Gems
      # One gem that the user names, in the words of zr's `--gem`:
      #
      #   rack          the newest release
      #   rack=3.1.8    that version
      #   ./src/rack    an unpacked gem (a word with a `/` is a path)
      Request = Data.define(:name, :version, :path) do
        def self.parse(word)
          return new(name: nil, version: nil, path: File.expand_path(word)) if word.include?("/")

          name, version = word.split("=", 2)
          unless name.match?(NAME) && (version.nil? || Gem::Version.correct?(version))
            raise ArgumentError, "#{word}: give NAME, NAME=VERSION or a path with a /"
          end

          new(name: name, version: version, path: nil)
        end

        # The versions that the request accepts.
        def requirement = version ? Gem::Requirement.new(version) : Gem::Requirement.default

        # The name for a row and a log, before the gem is found.
        def label = name || File.basename(path)

        def to_s = path || [name, version].compact.join("=")
      end
    end
  end
end
