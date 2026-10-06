# A file found through a $LOAD_PATH directory that is a symlink has the
# path of the file the link names, as ruby expands its load path;
# require_relative and load keep the path as written.
require "tmpdir"

Dir.mktmpdir do |tmp|
  Dir.mkdir(File.join(tmp, "real"))
  File.symlink("real", File.join(tmp, "link"))
  File.write(File.join(tmp, "real", "linked_lib.rb"), "LINKED = [__FILE__, __dir__]\n")
  File.write(File.join(tmp, "real", "rel_lib.rb"), "REL = __FILE__\n")
  File.write(File.join(tmp, "real", "loaded_lib.rb"), "$loaded = __FILE__\n")
  real = File.realpath(tmp)
  $LOAD_PATH.unshift(File.join(tmp, "link"))
  require "linked_lib"
  p LINKED.map { it.sub(real, "TMP") }
  p $LOADED_FEATURES.last.sub(real, "TMP")
  require_relative File.join(tmp, "link", "rel_lib")
  p REL.sub(tmp, "TMP")
  load File.join(tmp, "link", "loaded_lib.rb")
  p $loaded.sub(tmp, "TMP")
  $LOAD_PATH.shift
end

# A frozen $LOADED_FEATURES takes no feature: the file runs, then the
# require raises.
Dir.mktmpdir do |tmp|
  File.write(File.join(tmp, "frozen_lib.rb"), "puts 'ran'\n")
  $LOAD_PATH.unshift(tmp)
  $LOADED_FEATURES.freeze
  begin
    require "frozen_lib"
  rescue RuntimeError => e
    p e.message
  end
end
