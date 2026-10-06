# A Warning#warn that calls super reaches Kernel#warn with Warning as
# self, which writes the text, so there is no recursion.
$stderr = $stdout
module Warning
  def warn(*args, **kwargs)
    super
  end
end
warn "avoid infinite recursion"
