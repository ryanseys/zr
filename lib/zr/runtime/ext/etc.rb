# frozen_string_literal: true

# The user, group and system tables the C library keeps. Ruby ships this
# as an extension; the rows come from getpwnam and its family.
require "rbconfig"
Object.send(:native_module, :Etc)
require "etc_names"

module Etc
  # The version of the etc gem whose C this file ports.
  VERSION = "1.4.6"

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
    row = Primitive.zr_pw_name(Etc.send(:string_arg, name))
    raise ArgumentError, "can't find user for #{name}" unless row

    Passwd.new(*row)
  end

  def getpwuid(uid = (given = false; nil))
    uid = Process.uid if given == false
    row = Primitive.zr_pw_uid(Integer.send(:int_operand, uid))
    raise ArgumentError, "can't find user for #{uid}" unless row

    Passwd.new(*row)
  end

  def getgrnam(name)
    row = Primitive.zr_gr_name(Etc.send(:string_arg, name))
    raise ArgumentError, "can't find group for #{name}" unless row

    Group.new(*row)
  end

  def getgrgid(gid = (given = false; nil))
    gid = Process.gid if given == false
    row = Primitive.zr_gr_gid(Integer.send(:int_operand, gid))
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

  def confstr(name) = Etc.send(:checked, "confstr", Primitive.zr_confstr(Integer.send(:int_operand, name)))
  def sysconf(name) = Etc.send(:checked, "sysconf", Primitive.zr_sysconf(Integer.send(:int_operand, name)))

  # A walk of the table inside another walk of it raises, as etc.c's
  # passwd_blocking and group_blocking do.
  def each_row(reader)
    table = reader == :getpwent ? "passwd" : "group"
    raise RuntimeError, "parallel #{table} iteration" if Etc.instance_variable_get(:"@#{table}_walking")

    begin
      Etc.instance_variable_set(:"@#{table}_walking", true)
      __send__(reader == :getpwent ? :setpwent : :setgrent)
      while (row = __send__(reader))
        yield row
      end
      nil
    ensure
      __send__(reader == :getpwent ? :endpwent : :endgrent)
      Etc.instance_variable_set(:"@#{table}_walking", false)
    end
  end

  # StringValue: a String, or an object that converts to one.
  def string_arg(name)
    return name if name.is_a?(String)
    raise TypeError, "no implicit conversion of #{conversion_name(name)} into String" unless name.respond_to?(:to_str)

    name.to_str
  end

  # A negative Integer is the errno of a failed call.
  def checked(call, got)
    raise SystemCallError.new(call, -got) if got.is_a?(Integer) && got.negative?

    got
  end
  private :each_row, :string_arg, :checked
  private_class_method :each_row, :string_arg, :checked
end

class IO
  # etc's io_pathconf: fpathconf(3) on the stream's descriptor, and nil
  # for a limit that the system does not have.
  def pathconf(name)
    got = Primitive.zr_io_fpathconf(fileno, IO.send(:c_int, name))
    raise SystemCallError.new("fpathconf", -got) if got.is_a?(Integer) && got.negative?

    got
  end
end
