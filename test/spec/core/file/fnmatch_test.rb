# frozen_string_literal: true

require "spec_helper"

describe "File: fnmatch" do
  it "fnmatch matches wildcards, sets and case as dir.c does" do
    result = zr(<<~'RUBY')
      # fnmatch matches as dir.c's does: a wildcard takes a newline, a trailing
      # backslash matches nothing, a set reads its members as they are, and
      # FNM_CASEFOLD folds ASCII alone.
      cases = [["*", "\n"], ["?", "\n"], ["a*", "a\nb"], ["\\", "\\"], ["a\\", "a\\"], ["[z-a]", "b"], ["[a\\-c]", "b"],
               ["[a\\-c]", "-"], ["[]a]", "]"], ["[!]", "!"], ["[a-]", "-"], ["\\*", "*"], ["a[", "a["], ["[", "["]]
      cases.each { |pattern, path| p [pattern, path, File.fnmatch(pattern, path)] }
      p File.fnmatch("É", "é", File::FNM_CASEFOLD), File.fnmatch("A", "a", File::FNM_CASEFOLD)
      # bracket reads the case of the byte after a member, as CRuby does.
      p File.fnmatch("[abc]", "]", File::FNM_CASEFOLD), File.fnmatch("[^a]", "]", File::FNM_CASEFOLD)
    RUBY

    _(result).must_answer <<~'OUT'
      ["*", "\n", true]
      ["?", "\n", true]
      ["a*", "a\nb", true]
      ["\\", "\\", false]
      ["a\\", "a\\", false]
      ["[z-a]", "b", false]
      ["[a\\-c]", "b", false]
      ["[a\\-c]", "-", true]
      ["[]a]", "]", false]
      ["[!]", "!", true]
      ["[a-]", "-", true]
      ["\\*", "*", true]
      ["a[", "a[", false]
      ["[", "[", false]
      false
      true
      true
      false
    OUT
  end

  it "FNM_EXTGLOB expands braces as ruby_brace_expand does" do
    result = zr(<<~'RUBY')
      # FNM_EXTGLOB expands braces as ruby_brace_expand does: a backslash hides
      # a brace or a comma, and a brace that never closes gives no pattern.
      e = File::FNM_EXTGLOB
      p File.fnmatch("{a,b}", "b", e), File.fnmatch("{a,b", "{a,b", e), File.fnmatch("\\{a}", "{a}", e),
        File.fnmatch("{a\\,b}", "a,b", e), File.fnmatch("{a,{b,c}}", "c", e), File.fnmatch("{,a}", "", e),
        File.fnmatch("{a,b}", "{a,b}", e | File::FNM_NOESCAPE)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      true
      true
      true
      true
      false
    OUT
  end

  it "FNM_PATHNAME's double star takes any number of directories, and the pattern is a C string" do
    result = zr(<<~'RUBY')
      # With FNM_PATHNAME a "**/" takes any number of directories, and a
      # hidden one only with FNM_DOTMATCH.
      pn = File::FNM_PATHNAME
      p File.fnmatch("**/b", "a/x/y/b", pn), File.fnmatch("**/b", "b", pn), File.fnmatch("**/b", ".x/b", pn),
        File.fnmatch("**/b", ".x/b", pn | File::FNM_DOTMATCH), File.fnmatch("*/b", "a/x/b", pn), File.fnmatch("a/**/b", "a/b", pn)
      # The pattern is a C string; the path is a path.
      p((File.fnmatch("a\0", "a") rescue $!), (File.fnmatch("a", "a\0") rescue $!), (File.fnmatch(:a, "a") rescue $!))
      p File.fnmatch("a".encode("utf-16le"), "a"), (File.fnmatch("*", "a".encode("utf-16le")) rescue $!)
      p File.fnmatch("あ*".encode("euc-jp"), "あい".encode("euc-jp"))
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      false
      true
      false
      true
      #<ArgumentError: string contains null byte>
      #<ArgumentError: path name contains null byte>
      #<TypeError: no implicit conversion of Symbol into String>
      false
      #<Encoding::CompatibilityError: path name must be ASCII-compatible (UTF-16LE): "a">
      true
    OUT
  end
end
