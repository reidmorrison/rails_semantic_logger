class PayloadCollector
  class << self
    def wrap
      @store = true
      yield
    ensure
      @store = false
    end

    def append(payload)
      data.append(payload) if @store
    end

    def last
      data.last
    end

    def flush
      @data = []
    end

    private

    def data
      @data ||= []
    end
  end
end
