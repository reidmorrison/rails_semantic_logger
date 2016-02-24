ActionView::LogSubscriber
module ActionView
  class LogSubscriber
    def info(message = nil, &block)
      debug(message, &block)
    end

    def info?
      debug?
    end
  end
end
