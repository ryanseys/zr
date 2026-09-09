# File and Dir: the path functions, which are pure, and the few
# questions a program asks the file system about a path.
class IO; end

class File < IO
  SEPARATOR = "/"
  ALT_SEPARATOR = nil
  PATH_SEPARATOR = ":"

  def self.basename(path, suffix = nil)
    raise TypeError, "no implicit conversion of #{path.class} into String" unless path.is_a?(String)

    return "/" if path.delete("/").empty? && !path.empty?

    name = path.split("/").reject(&:empty?).last || ""
    return name if suffix.nil? || name == suffix

    if suffix == ".*"
      dot = name.rindex(".")
      return dot && dot > 0 ? name[0, dot] : name
    end
    name.end_with?(suffix) ? name[0, name.size - suffix.size] : name
  end

  def self.dirname(path, level = 1)
    raise TypeError, "no implicit conversion of #{path.class} into String" unless path.is_a?(String)

    level.times do
      parts = path.split("/").reject(&:empty?)
      parts.pop
      path = if parts.empty? then path.start_with?("/") ? "/" : "."
             else (path.start_with?("/") ? "/" : "") + parts.join("/")
             end
    end
    path
  end

  def self.extname(path)
    name = basename(path)
    dot = name.rindex(".")
    return "" if dot.nil? || dot == 0 || dot == name.size - 1

    name[dot..]
  end

  def self.split(path) = [dirname(path), basename(path)]

  def self.join(*parts)
    parts.flatten.each_with_index.map do |part, i|
      raise TypeError, "no implicit conversion of #{part.class} into String" unless part.is_a?(String)

      part = part.delete_prefix("/") if i > 0 && part.start_with?("/")
      part = part.delete_suffix("/") if i < parts.size - 1 && part.end_with?("/") && part.size > 1
      part
    end.join("/")
  end

  def self.absolute_path?(path) = path.start_with?("/")

  def self.expand_path(path, dir = nil)
    raise TypeError, "no implicit conversion of #{path.class} into String" unless path.is_a?(String)
    Primitive.zr_unimplemented("File.expand_path with a home directory") if path.start_with?("~") || (dir && dir.start_with?("~"))

    base = if path.start_with?("/") then ""
           elsif dir.nil? then Dir.pwd
           elsif dir.start_with?("/") then dir
           else "#{Dir.pwd}/#{dir}"
           end
    parts = []
    "#{base}/#{path}".split("/").each do |part|
      case part
      when "", "." then nil
      when ".." then parts.pop
      else parts << part
      end
    end
    "/" + parts.join("/")
  end

  def self.absolute_path(path, dir = nil) = expand_path(path, dir)

  def self.exist?(path) = Primitive.zr_path_kind(path) != 0
  def self.file?(path) = Primitive.zr_path_kind(path) == 2
  def self.directory?(path) = Primitive.zr_path_kind(path) == 1

  def self.read(path) = Primitive.zr_unimplemented("File.read")
  def self.write(path, content) = Primitive.zr_unimplemented("File.write")
  def self.open(path, mode = "r") = Primitive.zr_unimplemented("File.open")
end

class Dir
  def self.pwd = Primitive.zr_getcwd
  def self.exist?(path) = Primitive.zr_path_kind(path) == 1
end
