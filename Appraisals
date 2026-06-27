# TODO: revert to rubygems once semantic_logger 5.0 is released
semantic_logger_git = {github: "reidmorrison/semantic_logger", branch: "main"}

appraise "rails_7.2" do
  gem "rails", "~> 7.2.0"
  gem "semantic_logger", **semantic_logger_git
end

appraise "rails_8.0" do
  gem "rails", "~> 8.0.0"
  gem "semantic_logger", **semantic_logger_git
end

appraise "rails_8.1" do
  gem "rails", "~> 8.1.1"
  gem "semantic_logger", **semantic_logger_git
end
