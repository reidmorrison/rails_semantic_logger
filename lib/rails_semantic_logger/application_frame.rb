module RailsSemanticLogger
  # The application code behind a log entry: the first frame that the application's backtrace cleaner
  # keeps, on the stack that led to the entry (.on_stack) or in an exception's backtrace (.in_backtrace).
  #
  # Rails' verbose_*_logs options write that frame as the entry's source (#source), wherever it is. It
  # is the entry's call site (#call_site, see SemanticLogger.call_site_level) only when Rails did not
  # take over from the application before reaching it: application code further out, such as an
  # around_action or a worker's middleware, did not cause what Rails then logged.
  class ApplicationFrame
    # This gem's own code, which is never the application code behind an entry: lib/rails_semantic_logger/
    # and lib/rails_semantic_logger.rb, as Ruby loaded them.
    OWN_PATHS = ["#{File.dirname(__FILE__)}/", "#{File.dirname(__FILE__)}.rb"].freeze

    # Where Rails dispatches an action, and renders its template once the action has returned.
    ACTION_DISPATCH_PATHS = %w[
      /action_controller/metal/basic_implicit_render.rb /action_controller/metal/implicit_render.rb
    ].freeze

    # Where Active Job performs a job from its serialized form (Base.execute), as a worker does with a job
    # that it took from its queue, and as the inline and test adapters do.
    JOB_EXECUTION_PATH = "/active_job/execution.rb".freeze

    # The name Rails gives the method of a compiled template, such as
    # "_app_views_orders_show_html_erb__1935574751676049736_7680", with numbers that change on every boot,
    # as matched by Rails' own backtrace cleaner's RENDER_TEMPLATE_PATTERN.
    COMPILED_TEMPLATE_METHOD = /\A_\w+_{2,3}\d+_\d+\z/

    # Returns [ApplicationFrame] the application code on the current call stack, skipping this gem's own
    # frames. Without for_source the walk stops where Rails took over, since a frame beyond it is not the
    # entry's call site.
    def self.on_stack(backtrace_cleaner, for_source: false)
      took_over = false
      Thread.each_caller_location do |location|
        next if location.path.start_with?(*OWN_PATHS)

        took_over ||= rails_took_over?(location)
        return new(backtrace_cleaner, nil, took_over: true) if took_over && !for_source
        return new(backtrace_cleaner, location, took_over: took_over) if backtrace_cleaner.clean_frame(location)
      end
      new(backtrace_cleaner, nil, took_over: took_over)
    end

    # Returns [ApplicationFrame] the application code in the exception's backtrace, where it raised the
    # exception. The search stops where Rails took over, as for an exception that Rails raised while it
    # rendered an action's template.
    def self.in_backtrace(exception, backtrace_cleaner)
      (exception.backtrace_locations || []).each do |location|
        return new(backtrace_cleaner, nil, took_over: true) if rails_took_over?(location)
        return new(backtrace_cleaner, location) if backtrace_cleaner.clean_frame(location)
      end
      new(backtrace_cleaner, nil)
    end

    # Whether Rails, at this frame, takes over from the application's code to run code of its own: it
    # dispatches an action and renders its template once the action has returned, or performs a job from
    # its serialized form.
    def self.rails_took_over?(location)
      path = location.path.to_s
      path.end_with?(*ACTION_DISPATCH_PATHS) ||
        (path.end_with?(JOB_EXECUTION_PATH) && base_label(location) == "execute")
    end
    private_class_method :rails_took_over?

    # Returns [String|nil] the frame's method name. Rails 7.2 and 8.0 give the line with a SyntaxError
    # a frame that has none.
    def self.base_label(location)
      location.base_label if location.respond_to?(:base_label)
    end

    # A Thread::Backtrace::Location, or, in the backtrace of a SyntaxError that Rails wraps, a frame
    # that responds to #path and #lineno, and may have a #label and #base_label.
    attr_reader :location

    def initialize(backtrace_cleaner, location, took_over: false)
      @backtrace_cleaner = backtrace_cleaner
      @location          = location
      @took_over         = took_over
    end

    # Returns [String|nil] the frame as the backtrace cleaner writes it, such as
    # "app/models/user.rb:12:in 'User.recent'", which Rails logs as the "↳ source" of an entry. nil when
    # the cleaner keeps no frame.
    def source
      # A String: Rails 8.0+'s cleaner returns the location unchanged when BACKTRACE is set.
      @backtrace_cleaner.clean_frame(location).to_s if location
    end

    # Returns [Thread::Backtrace::Location|SemanticLogger::CallSite|nil] the entry's call site, or nil
    # when there is no application frame, or Rails took over before it. Another frame becomes a call
    # site with its path, line and label, as Semantic Logger records a location. A frame in a compiled
    # template has no label, since Rails names the template's method with numbers that change on
    # every boot.
    def call_site
      return if location.nil? || @took_over

      compiled = COMPILED_TEMPLATE_METHOD.match?(self.class.base_label(location).to_s)
      return location if location.is_a?(Thread::Backtrace::Location) && !compiled

      label = location.label&.to_s if !compiled && location.respond_to?(:label)
      SemanticLogger::CallSite.new(path: -location.path.to_s, line: location.lineno.to_i, label: label && -label)
    end
  end
end
