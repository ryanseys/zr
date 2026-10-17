# ruby loads rubygems and bundled_gems before the program's first line,
# so $LOADED_FEATURES lists them from the start. zr loads them at the
# first use of Gem, which keeps a program's start as fast as ruby's with
# --disable-gems; until then they are not listed. (bundled_gems'
# LoadError#message is copied: stdlib/rubygems/a_load_error_whose_path_…)
p $LOADED_FEATURES.grep(/(rubygems|bundled_gems)\.rb\z/).map { |f| File.basename(f) }
