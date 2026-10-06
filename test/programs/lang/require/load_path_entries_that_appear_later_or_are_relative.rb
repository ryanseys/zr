# A $LOAD_PATH entry that is no directory yet is looked at again by the
# next require, and a relative entry follows the working directory.
require "tmpdir"

Dir.mktmpdir do |root|
  later = File.join(root, "later")
  $LOAD_PATH.unshift(later)
  begin
    require "appears_later"
  rescue LoadError => e
    p e.message
  end
  Dir.mkdir(later)
  File.write(File.join(later, "appears_later.rb"), "p :appeared\n")
  p require("appears_later")

  %w[one two].each do |name|
    Dir.mkdir(File.join(root, name))
    Dir.mkdir(File.join(root, name, "rel"))
    File.write(File.join(root, name, "rel", "relative_#{name}.rb"), "p :#{name}\n")
  end
  $LOAD_PATH.unshift("rel")
  Dir.chdir(File.join(root, "one")) { p require("relative_one") }
  Dir.chdir(File.join(root, "two")) { p require("relative_two") }
  Dir.chdir(File.join(root, "two")) do
    begin
      require "relative_one"
    rescue LoadError => e
      p e.message
    end
  end
  $LOAD_PATH.delete("rel")
  $LOAD_PATH.delete(later)
end
