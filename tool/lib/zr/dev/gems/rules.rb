# frozen_string_literal: true

require_relative "../../../../../lib/zr/library/ports"

module Zr
  module Dev
    module Gems
      # What zr refuses before any build, from the gems' metadata alone,
      # as `zr build` refuses it (lib/zr/gem_set/resolve.rb):
      #
      #   port-range:<name>  a gem that zr ports, at a version outside the
      #                      versions whose C the port implements
      #
      # A gem with a C extension that zr has no port of builds but for its
      # C part; the trial reads which from the build's warnings (`cext:`).
      module Rules
        module_function

        # The Failure for the first gem of `subjects` that zr refuses, or nil.
        def refusal(subjects)
          subjects.each do |subject|
            port = Library::Ports::ALL[subject.name]
            if port
              next if Library::Ports.requirement(port.compat).satisfied_by?(Gem::Version.new(subject.version))

              return Failure.new("port-range:#{subject.name}",
                                 "#{subject}: zr implements the C part of #{subject.name} #{port.compat} only", tier: :refused)
            end
          end
          nil
        end
      end
    end
  end
end
