# frozen_string_literal: true

# The load that CRuby's prelude makes on the first `binding.irb`: irb, the
# pinned gem, included without changes. A program that calls `irb` by
# name includes this file before its body. The load waits for that first
# call, so irb joins $LOADED_FEATURES only then.
#
# irb finds the messages for its locale by walking $LOAD_PATH and taking
# the first file it can read. A program here has no library on disk and
# includes its files instead, so the same walk looks in the program's
# included files. The result is a path, as irb expects, and
# `Kernel.load` runs it as irb intends. The module is nameless because
# this file is the program's own, and a constant written here is one
# that ruby does not have.
Binding.send(:irb_session=, lambda do
  require "irb"
  IRB::Locale.prepend(Module.new do
    def find(file, paths = $LOAD_PATH)
      dir = File.dirname(file)
      # `each_localized_path` yields the names that irb wants, the most
      # specific locale first. It is called with a block: without one
      # it returns an enumerator that cannot be walked.
      wanted = []
      each_localized_path(dir == "." ? "" : dir, File.basename(file)) { |name| wanted << name }
      wanted.filter_map { |name| Kernel.search(name) }.first || super
    end
  end)
end)
