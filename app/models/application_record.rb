class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
  def short_name
    self.try(:name) || self.try(:title) || self.try(:body) || "#{self.class_name}_#{id}"
  end
end
