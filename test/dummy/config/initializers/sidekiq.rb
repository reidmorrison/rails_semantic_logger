# In tests we force Sidekiq into thinking it is running as a server,
# so it creates a stdout logger. Remove it here:
Rails.application.config.after_initialize do
  SemanticLogger.appenders.delete_if { |appender| appender.is_a?(SemanticLogger::Appender::IO) } if Rails.env.test?
end
