# racc's parser loads before prism here, as the parser gem's does. Each
# autoload that prism declares still loads where the program sees it:
# Prism::Translation has its names, and Prism::Translation::Parser's file
# is in $LOADED_FEATURES once the program reads the name.
require "racc/parser"
require "prism"
translation = Prism::Translation
p translation.constants.sort.first(3)
p translation.autoload?(:Parser)
p $LOADED_FEATURES.count { |path| path.end_with?("/prism/translation.rb") }
p translation.const_defined?(:Ripper, false), translation.autoload?(:Ripper)
