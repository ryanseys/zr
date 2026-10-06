# const_source_location of a name whose autoload file runs now gives the
# autoload's place until the file defines it, then the definition's.
require "tmpdir"

module CslSpecs; end

Dir.mktmpdir do |dir|
  file = File.join(dir, "lib.rb")
  File.write(file, <<~RUBY)
    module CslSpecs
      BEFORE_DEFINE_LOCATION = const_source_location(:ConstSource)
      module ConstSource
        LOCATION = Object.const_source_location(name)
        INSIDE = CslSpecs.const_source_location(:ConstSource)
      end
    end
  RUBY
  CslSpecs.autoload :ConstSource, file
  shown = ->(loc) { [File.basename(loc[0]), loc[1]] }
  p shown.(CslSpecs.const_source_location(:ConstSource))
  p shown.(CslSpecs::ConstSource::LOCATION)
  p shown.(CslSpecs::ConstSource::INSIDE)
  p shown.(CslSpecs::BEFORE_DEFINE_LOCATION)
  p shown.(CslSpecs.const_source_location(:ConstSource))
  p CslSpecs.const_source_location(:Missing)
end
