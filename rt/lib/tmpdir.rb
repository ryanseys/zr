# The temporary-directory half of ruby's tmpdir: where scratch files
# go, and a directory that removes itself when its block ends.
class Dir
  # The first writable directory the environment names, else /tmp.
  def self.tmpdir
    named = [ENV["TMPDIR"], ENV["TMP"], ENV["TEMP"]].compact.find { |path| writable_directory?(path) }
    (named || "/tmp").chomp("/")
  end

  def self.writable_directory?(path)
    return false unless File.directory?(path)

    File.writable?(path)
  end
  private_class_method :writable_directory?

  # A fresh directory under `tmpdir`, named for the prefix and suffix
  # the caller asked for. With a block it is removed, and everything in
  # it, once the block ends.
  def self.mktmpdir(prefix_suffix = nil, tmpdir = nil, **options)
    path = make_tmpname(prefix_suffix, tmpdir || Dir.tmpdir, options)
    return path unless block_given?

    begin
      yield path
    ensure
      remove_tree(path)
    end
  end

  # The name ruby builds: prefix, the date, the process, six random
  # letters, suffix. A name already taken is tried again.
  def self.make_tmpname(prefix_suffix, base, options)
    prefix, suffix = case prefix_suffix
                     when nil then ["d", ""]
                     when String then [prefix_suffix, ""]
                     when Array then prefix_suffix
                     else raise ArgumentError, "unexpected prefix_suffix: #{prefix_suffix.inspect}"
                     end
    stamp = "#{Time.now.strftime('%Y%m%d')}-#{Process.pid}"
    loop do
      tail = (1..6).map { "abcdefghijklmnopqrstuvwxyz0123456789"[rand(36)] }.join
      path = File.join(base, "#{prefix}#{stamp}-#{tail}#{suffix}")
      next if File.exist?(path)

      Dir.mkdir(path, options[:mode] || 0o700)
      return path
    end
  end
  private_class_method :make_tmpname

  def self.remove_tree(path)
    return unless File.exist?(path)

    if File.directory?(path) && !File.symlink?(path)
      Dir.children(path).each { |name| remove_tree(File.join(path, name)) }
      Dir.rmdir(path)
    else
      File.unlink(path)
    end
  end
  private_class_method :remove_tree
end
