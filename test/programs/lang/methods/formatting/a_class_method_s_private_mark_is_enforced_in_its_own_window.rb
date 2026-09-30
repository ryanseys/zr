class CV
  def self.v = "cv1"
  private_class_method :v
end
p [(CV.v rescue $!.class.to_s), CV.send(:v)]
class CV
  def self.v = "cv2"
end
p CV.v

