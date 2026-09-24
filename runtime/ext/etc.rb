# The user, group and system tables the C library keeps. Ruby ships this
# as an extension; the rows come from getpwnam and its family.
require "rbconfig"
require "etc_names"

module Etc
  # The rows' members are the OS's own (etc_names). The two database
  # cursors are spelled on the row class as ruby spells them:
  # `Etc::Passwd.each` walks the same table `Etc.passwd` walks.
  Passwd = Struct.new(*PASSWD_MEMBERS)
  def Passwd.each(&block) = block ? Etc.passwd(&block) : to_enum(:each)

  if const_defined?(:GROUP_MEMBERS, false)
    Group = Struct.new(*GROUP_MEMBERS)
    def Group.each(&block) = block ? Etc.group(&block) : to_enum(:each)
  end

  module_function

  def getpwnam(name)
    row = Primitive.zr_pw_name(String(name))
    raise ArgumentError, "can't find user for #{name}" unless row

    Passwd.new(*row)
  end

  def getpwuid(uid = nil)
    uid = Process.uid if uid.nil?
    row = Primitive.zr_pw_uid(Integer(uid))
    raise ArgumentError, "can't find user for #{uid}" unless row

    Passwd.new(*row)
  end

  def getgrnam(name)
    row = Primitive.zr_gr_name(String(name))
    raise ArgumentError, "can't find group for #{name}" unless row

    Group.new(*row)
  end

  def getgrgid(gid = nil)
    gid = Process.gid if gid.nil?
    row = Primitive.zr_gr_gid(Integer(gid))
    raise ArgumentError, "can't find group for #{gid}" unless row

    Group.new(*row)
  end

  def setpwent = Primitive.zr_pw_rewind
  def endpwent = Primitive.zr_pw_done
  def setgrent = Primitive.zr_gr_rewind
  def endgrent = Primitive.zr_gr_done

  def getpwent
    row = Primitive.zr_pw_next
    row && Passwd.new(*row)
  end

  def getgrent
    row = Primitive.zr_gr_next
    row && Group.new(*row)
  end

  # Without a block the whole table comes back as an array, which is what
  # ruby does too.
  def passwd
    return each_row(:getpwent) { |row| yield row } if block_given?

    getpwent
  end

  def group
    return each_row(:getgrent) { |row| yield row } if block_given?

    getgrent
  end

  def each_passwd(&block) = block ? passwd(&block) : to_enum(:each_passwd)
  def each_group(&block) = block ? group(&block) : to_enum(:each_group)

  def nprocessors = Primitive.zr_nprocessors
  def getlogin = Primitive.zr_login_name
  def sysconfdir = RbConfig::CONFIG["sysconfdir"]
  def systmpdir = ENV["TMPDIR"] || "/tmp"

  def uname
    names = Primitive.zr_uname or raise SystemCallError.new("uname", Errno::EINVAL::Errno)
    %i[sysname nodename release version machine].zip(names).to_h
  end

  def confstr(name) = Primitive.zr_confstr(Integer(name))
  def sysconf(name) = Primitive.zr_sysconf(Integer(name))

  def each_row(reader)
    __send__(reader == :getpwent ? :setpwent : :setgrent)
    while (row = __send__(reader))
      yield row
    end
    nil
  ensure
    __send__(reader == :getpwent ? :endpwent : :endgrent)
  end
  private :each_row
  private_class_method :each_row
end
