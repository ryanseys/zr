class E < StandardError
  def detailed_message(**) = nil
end
begin; raise E, "x"; rescue => e; p e.full_message(highlight: false); end
raise E, "y"
