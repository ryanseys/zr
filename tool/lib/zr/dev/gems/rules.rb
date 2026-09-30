# frozen_string_literal: true

require_relative "../../../../../lib/zr/ports"

module Zr
  module Dev
    module Gems
      # What zr refuses before any build, from the gems' metadata alone,
      # as `zr build` refuses it (lib/zr/gem_set/resolve.rb):
      #
      #   cext:<name>        a gem with a C extension that zr has no port of
      #   port-range:<name>  a gem that zr ports, at a version outside the
      #                      versions whose C the port implements
      module Rules
        module_function

        # The Failure for the first gem of `subjects` that zr refuses, or nil.
        def refusal(subjects)
          subjects.each do |subject|
            port = Ports::ALL[subject.name]
            if port
              next if Gem::Requirement.new(port.compat).satisfied_by?(Gem::Version.new(subject.version))

              return Failure.new("port-range:#{subject.name}",
                                 "#{subject}: zr implements the C part of #{subject.name} #{port.compat} only", tier: :refused)
            end
            next unless subject.cext?

            return Failure.new("cext:#{subject.name}",
                               "#{subject} has a C extension (#{subject.extensions.join(", ")}), and zr has no port of it", tier: :refused)
          end
          nil
        end
      end
    end
  end
end
