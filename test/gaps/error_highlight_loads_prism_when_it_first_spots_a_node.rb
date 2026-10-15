# CRuby's error_highlight requires prism the first time it spots the node
# of an error, so prism's own Ruby code runs then, under any core method
# that the program has redefined. zr finds the node without loading
# prism's Ruby files, so the feature list does not change.
p $LOADED_FEATURES.grep(/prism\.rb\z/).size
begin
  1.foo
rescue NoMethodError => e
  e.detailed_message
end
p $LOADED_FEATURES.grep(/prism\.rb\z/).size
