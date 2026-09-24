# The load CRuby's prelude makes on the first `binding.irb`: irb, the
# pinned gem, carried unedited. A program that names `irb` carries
# this file ahead of its body, and the load waits for that first call,
# so irb joins $LOADED_FEATURES only then.
#
# irb finds the messages of the locale it runs under by walking
# $LOAD_PATH and taking the first file it can read. A program here
# stands on no library and carries its files instead, so the same walk
# asks what the program carries; what comes back is a path, as irb
# expects, and `Kernel.load` runs it the way irb means to. The module
# is nameless because this file is the program's own, and a constant
# written here is one ruby does not have.
Binding.send(:irb_session=, lambda do
  require "irb"
  IRB::Locale.prepend(Module.new do
    def find(file, paths = $LOAD_PATH)
      dir = File.dirname(file)
      # `each_localized_path` yields the names irb wants, the most
      # particular locale first. It is asked with a block: without one
      # it answers an enumerator that cannot be walked.
      wanted = []
      each_localized_path(dir == "." ? "" : dir, File.basename(file)) { |name| wanted << name }
      wanted.filter_map { |name| Kernel.search(name) }.first || super
    end
  end)
end)
