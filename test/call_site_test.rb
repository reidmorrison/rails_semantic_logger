require_relative "test_helper"

# With SemanticLogger.call_site_level on, each entry records where it was logged. Most of the entries
# that Rails Semantic Logger logs come from Rails' notifications, so the code that logs them is
# Active Support's. They record the application code behind them instead, or no call site at all.
module CallSiteTestHelpers
  # Records call sites at every level while the block runs.
  def with_call_sites
    call_site_level                = SemanticLogger.call_site_level
    SemanticLogger.call_site_level = :trace
    yield
  ensure
    SemanticLogger.call_site_level = call_site_level
  end

  # Gives the subscribers the cleaner while the block runs.
  def with_cleaner(cleaner, *subscribers)
    originals = subscribers.map(&:backtrace_cleaner)
    subscribers.each { |subscriber| subscriber.backtrace_cleaner = cleaner }
    yield
  ensure
    subscribers.zip(originals) { |subscriber, original| subscriber.backtrace_cleaner = original }
  end

  # A cleaner that keeps only the frames of this file, as the application's code.
  def this_file_cleaner
    ActiveSupport::BacktraceCleaner.new.tap do |cleaner|
      cleaner.remove_silencers!
      cleaner.add_silencer { |line| !line.include?(__FILE__) }
    end
  end

  # A cleaner that keeps no frame, as when none of the application's code is on the stack.
  def no_app_cleaner
    ActiveSupport::BacktraceCleaner.new.tap do |cleaner|
      cleaner.remove_silencers!
      cleaner.add_silencer { true }
    end
  end

  # Returns [path, line] of the entry's call site, or nil when it has none.
  def call_site(log)
    log.call_site&.file_name_and_line
  end

  def line_of(klass, method_name)
    klass.instance_method(method_name).source_location.last
  end
end

# An ActiveSupport::TestCase, so that its describe blocks have the helpers.
class CallSiteTest < ActiveSupport::TestCase
  include CallSiteTestHelpers

  class CallSiteJob < ActiveJob::Base
    def perform(value)
      value
    end
  end

  class CallSiteChildJob < CallSiteJob
  end

  # A frame with a path, line and label, as in a backtrace, or as Rails gives a SyntaxError's backtrace.
  BacktraceFrame = Struct.new(:path, :lineno, :base_label) do
    def label
      base_label
    end

    def to_s
      "#{path}:#{lineno}:in '#{label}'"
    end
  end

  class CallSiteMailer < ActionMailer::Base
    def note
      mail(to: "to@example.com", from: "from@example.com", subject: "Note", body: "Hi")
    end
  end

  describe "RailsSemanticLogger.record_call_sites_in_development" do
    before { @call_site_level = SemanticLogger.call_site_level }
    after { SemanticLogger.call_site_level = @call_site_level }

    it "records call sites at every level in development, rather than at Semantic Logger's level" do
      SemanticLogger.call_site_level = :error
      RailsSemanticLogger.record_call_sites_in_development(ActiveSupport::EnvironmentInquirer.new("development"))

      assert_equal :trace, SemanticLogger.call_site_level
    end

    it "keeps Semantic Logger's level in other environments" do
      SemanticLogger.call_site_level = :error
      RailsSemanticLogger.record_call_sites_in_development(ActiveSupport::EnvironmentInquirer.new("production"))

      assert_equal :error, SemanticLogger.call_site_level
    end
  end

  describe "RailsSemanticLogger.method_call_site" do
    it "returns where the class defines the method" do
      site = RailsSemanticLogger.method_call_site(CallSiteJob, :perform)

      assert_equal [__FILE__, line_of(CallSiteJob, :perform)], site.file_name_and_line
      assert_equal "CallSiteTest::CallSiteJob#perform", site.label
    end

    it "labels an inherited method with the class that defines it" do
      site = RailsSemanticLogger.method_call_site(CallSiteChildJob, :perform)

      assert_equal [__FILE__, line_of(CallSiteJob, :perform)], site.file_name_and_line
      assert_equal "CallSiteTest::CallSiteJob#perform", site.label
    end

    it "returns nil for a method that the class does not define" do
      assert_nil RailsSemanticLogger.method_call_site(CallSiteJob, :missing)
    end
  end

  describe RailsSemanticLogger::ApplicationFrame do
    # A cleaner that keeps every frame, as Rails' does when BACKTRACE is set.
    let(:keep_all_cleaner) { ActiveSupport::BacktraceCleaner.new.tap(&:remove_silencers!) }

    # Ruby gives code that it evaluates the path that it is given.
    def on_stack_from(path)
      eval("RailsSemanticLogger::ApplicationFrame.on_stack(keep_all_cleaner)", binding, path, 1) # rubocop:disable Style/EvalWithLocation
    end

    it "is the first frame on the stack that the cleaner keeps" do
      line  = __LINE__ + 1
      frame = RailsSemanticLogger::ApplicationFrame.on_stack(keep_all_cleaner)

      assert_equal [__FILE__, line], [frame.call_site.path, frame.call_site.lineno]
      assert_match(/\A#{Regexp.escape(__FILE__)}:#{line}:/, frame.source)
    end

    it "skips the frames of this gem's own code" do
      # A path in this gem's code, as Ruby loaded it.
      subscriber = RailsSemanticLogger::ActiveRecord::LogSubscriber.instance_method(:sql).source_location.first
      frame      = on_stack_from(File.join(File.dirname(subscriber), "fake.rb"))

      assert_equal [__FILE__, line_of(self.class, :on_stack_from) + 1], [frame.call_site.path, frame.call_site.lineno]
    end

    it "keeps the frames of an application's own file with the same name" do
      frame = on_stack_from("/app/lib/rails_semantic_logger/fake.rb")

      assert_equal ["/app/lib/rails_semantic_logger/fake.rb", 1], [frame.call_site.path, frame.call_site.lineno]
    end

    it "is the call site, and the source, of the application frame" do
      location = caller_locations(0, 1).first
      frame    = RailsSemanticLogger::ApplicationFrame.new(keep_all_cleaner, location)

      assert_same location, frame.call_site
      assert_equal location.to_s, frame.source
    end

    it "is not the call site when Rails took over before it, but is still the source" do
      location = caller_locations(0, 1).first
      frame    = RailsSemanticLogger::ApplicationFrame.new(keep_all_cleaner, location, took_over: true)

      assert_nil frame.call_site
      assert_equal location.to_s, frame.source
    end

    it "leaves out the label of a compiled template's method, which changes on every boot" do
      method   = "_app_views_orders_show_html_erb__1935574751676049736_7680"
      location = BacktraceFrame.new("/app/views/orders/show.html.erb", 3, method)
      site     = RailsSemanticLogger::ApplicationFrame.new(keep_all_cleaner, location).call_site

      assert_equal ["/app/views/orders/show.html.erb", 3], site.file_name_and_line
      assert_nil site.label
    end

    describe ".in_backtrace" do
      def exception_with(*locations)
        Struct.new(:backtrace_locations).new(locations)
      end

      # Keeps only the frames under /app/.
      let(:app_cleaner) do
        ActiveSupport::BacktraceCleaner.new.tap do |cleaner|
          cleaner.remove_silencers!
          cleaner.add_silencer { |line| !line.start_with?("/app/") }
        end
      end

      # Its frames are not Thread::Backtrace::Locations, so the call site is made from the frame's
      # path, line and label.
      it "is where the application raised the exception" do
        app   = BacktraceFrame.new("/app/models/order.rb", 12, "submit")
        rails = BacktraceFrame.new("/gems/activerecord/lib/active_record/base.rb", 9, "save")
        site  = RailsSemanticLogger::ApplicationFrame.in_backtrace(exception_with(rails, app), app_cleaner).call_site

        assert_equal ["/app/models/order.rb", 12], site.file_name_and_line
        assert_equal "submit", site.label
      end

      # Rails wraps a SyntaxError, such as one in a file that it loads on demand, and gives its
      # backtrace frames of its own, which are not Thread::Backtrace::Locations: first the line with
      # the error, read from the message, then a proxy for each frame of the SyntaxError's backtrace.
      describe "of a SyntaxError" do
        def syntax_error
          eval("def broken(", binding, "/app/models/broken.rb", 3) # rubocop:disable Style/EvalWithLocation
        rescue SyntaxError => e
          ActiveSupport::SyntaxErrorProxy.new(e)
        end

        it "is the line with the error" do
          site = RailsSemanticLogger::ApplicationFrame.in_backtrace(syntax_error, app_cleaner).call_site

          assert_equal ["/app/models/broken.rb", 3], site.file_name_and_line
        end

        it "labels a proxy for a frame as Semantic Logger labels a location" do
          error    = syntax_error
          expected = error.__getobj__.backtrace_locations.find { |location| location.path == __FILE__ }
          site     = RailsSemanticLogger::ApplicationFrame.in_backtrace(error, this_file_cleaner).call_site

          assert_equal [expected.path, expected.lineno, expected.label], [site.path, site.line, site.label]
        end
      end

      # As for an exception that Rails raised while rendering an action's template, inside an
      # around_action.
      it "stops where Rails took over" do
        path      = "/gems/actionpack/lib/action_controller/metal/implicit_render.rb"
        render    = BacktraceFrame.new(path, 37, "default_render")
        around    = BacktraceFrame.new("/app/controllers/orders_controller.rb", 5, "switch_locale")
        exception = exception_with(render, around)

        assert_nil RailsSemanticLogger::ApplicationFrame.in_backtrace(exception, app_cleaner).call_site
      end
    end
  end

  describe "RailsSemanticLogger.call_site?" do
    let(:logger) { SemanticLogger["CallSiteTest"] }

    it "is true at and above the call site level" do
      with_call_sites do
        SemanticLogger.call_site_level = :info

        assert RailsSemanticLogger.call_site?(logger, :info)
        refute RailsSemanticLogger.call_site?(logger, :debug)
      end
    end

    it "is false when the logger does not log at the level" do
      with_call_sites do
        logger.level = :warn

        refute RailsSemanticLogger.call_site?(logger, :info)
      end
    end

    it "is false when call sites are off" do
      with_call_sites do
        SemanticLogger.call_site_level = nil

        refute RailsSemanticLogger.call_site?(logger, :fatal)
      end
    end
  end

  describe "Active Record" do
    let(:subscriber) { RailsSemanticLogger::ActiveRecord::LogSubscriber }

    it "records the code that ran the query" do
      line     = nil
      messages = with_call_sites do
        with_cleaner(this_file_cleaner, subscriber) do
          semantic_logger_events do
            line = __LINE__ + 1
            Sample.where(name: "call site").first
          end
        end
      end

      assert_equal [__FILE__, line], call_site(messages.first)
    end

    it "records no call site when no application code ran the query" do
      messages = with_call_sites do
        with_cleaner(no_app_cleaner, subscriber) do
          semantic_logger_events { Sample.where(name: "call site").first }
        end
      end

      assert_nil messages.first.call_site
    end

    it "records no call site when call sites are off" do
      messages = with_cleaner(this_file_cleaner, subscriber) do
        semantic_logger_events { Sample.where(name: "call site").first }
      end

      assert_nil messages.first.call_site
    end

    # The entry is logged at :debug, so the backtrace follows whether :debug is at or above the
    # backtrace level, whatever the logger's own level, which in the dummy application is :trace.
    it "logs the backtrace from the application code when the logger's level is below the entry's" do
      messages = with_backtrace_level(:debug) do
        semantic_logger_events { Sample.where(name: "call site").first }
      end

      assert_includes messages.first.backtrace.first, __FILE__
    end
  end

  describe "Active Job" do
    let(:subscriber) { RailsSemanticLogger::ActiveJob::LogSubscriber }

    it "records the code that performed the job" do
      line     = nil
      messages = with_call_sites do
        with_cleaner(this_file_cleaner, subscriber) do
          semantic_logger_events do
            line = __LINE__ + 1
            CallSiteJob.perform_now(1)
          end
        end
      end

      assert_equal 2, messages.count, messages
      messages.each { |message| assert_equal [__FILE__, line], call_site(message), message.message }
    end

    it "records the job's #perform when no application code performed it" do
      messages = with_call_sites do
        with_cleaner(no_app_cleaner, subscriber) do
          semantic_logger_events { CallSiteJob.perform_now(1) }
        end
      end

      assert_equal 2, messages.count, messages
      messages.each do |message|
        assert_equal [__FILE__, line_of(CallSiteJob, :perform)], call_site(message)
        assert_equal "CallSiteTest::CallSiteJob#perform", message.call_site.label
      end
    end

    # As a worker does, with its own code, such as middleware, further out on the stack.
    it "records the job's #perform for a job taken from its queue" do
      messages = with_call_sites do
        with_cleaner(this_file_cleaner, subscriber) do
          semantic_logger_events { ActiveJob::Base.execute(CallSiteJob.new(1).serialize) }
        end
      end

      assert_equal 2, messages.count, messages
      messages.each { |message| assert_equal [__FILE__, line_of(CallSiteJob, :perform)], call_site(message) }
    end
  end

  describe "Action Mailer" do
    let(:subscriber) { RailsSemanticLogger::ActionMailer::LogSubscriber }

    it "records the code that delivered the mail" do
      line     = nil
      messages = with_call_sites do
        with_cleaner(this_file_cleaner, subscriber) do
          semantic_logger_events do
            line = __LINE__ + 1
            CallSiteMailer.note.deliver_now
          end
        end
      end

      assert_equal 2, messages.count, messages
      messages.each { |message| assert_equal [__FILE__, line], call_site(message), message.message }
    end

    it "records the mailer's action, or else no call site, when no application code delivered the mail" do
      messages = with_call_sites do
        with_cleaner(no_app_cleaner, subscriber) do
          semantic_logger_events { CallSiteMailer.note.deliver_now }
        end
      end

      processed = messages.find { |message| message.message.include?("processed outbound mail") }
      delivered = messages.find { |message| message.message.start_with?("Delivered mail") }

      assert_equal [__FILE__, line_of(CallSiteMailer, :note)], call_site(processed)
      assert_nil delivered.call_site
    end

    # As deliver_later does, with the worker's own code further out on the stack.
    it "records the mailer's action, or else no call site, for mail delivered by a job" do
      job      = ActionMailer::MailDeliveryJob.new(CallSiteMailer.name, "note", "deliver_now", args: [])
      messages = with_call_sites do
        with_cleaner(this_file_cleaner, subscriber, RailsSemanticLogger::ActiveJob::LogSubscriber) do
          semantic_logger_events { ActiveJob::Base.execute(job.serialize) }
        end
      end

      processed = messages.find { |message| message.message.include?("processed outbound mail") }
      delivered = messages.find { |message| message.message.start_with?("Delivered mail") }

      assert_equal [__FILE__, line_of(CallSiteMailer, :note)], call_site(processed)
      assert_nil delivered.call_site
    end
  end

  describe "Action View" do
    it "records the code that rendered the template" do
      line     = nil
      messages = with_call_sites do
        with_cleaner(this_file_cleaner, RailsSemanticLogger::ActionView::LogSubscriber) do
          semantic_logger_events do
            line = __LINE__ + 1
            ApplicationController.render(template: "articles/new", layout: false)
          end
        end
      end

      rendered = messages.find { |message| message.message == "Rendered" }

      assert_equal [__FILE__, line], call_site(rendered)
    end

    it "records the line of the template that rendered a partial, without the template method's name" do
      messages = with_call_sites do
        with_cleaner(Rails::BacktraceCleaner.new, RailsSemanticLogger::ActionView::LogSubscriber) do
          semantic_logger_events { ApplicationController.render(template: "articles/with_partial", layout: false) }
        end
      end

      partial = messages.find { |message| message.payload&.dig(:partial)&.include?("_title") }

      assert_equal [Rails.root.join("app/views/articles/with_partial.html.erb").to_s, 1], call_site(partial)
      assert_nil partial.call_site.label
    end
  end

  describe "an exception that a request raised" do
    let(:request) { ActionDispatch::Request.new(Rack::MockRequest.env_for("/", Rails.application.env_config)) }

    def raise_here
      raise ArgumentError, "Failed"
    rescue ArgumentError => e
      e
    end

    def log_error(exception, cleaner)
      wrapper = ActionDispatch::ExceptionWrapper.new(cleaner, exception)
      with_call_sites do
        semantic_logger_events do
          ActionDispatch::DebugExceptions.new(->(_env) {}).send(:log_error, request, wrapper)
        end
      end
    end

    it "records where the application raised it" do
      messages = log_error(raise_here, this_file_cleaner)

      assert_equal 1, messages.count, messages
      assert_equal [__FILE__, line_of(self.class, :raise_here) + 1], call_site(messages.first)
    end

    it "records no call site when none of its frames is the application's" do
      messages = log_error(raise_here, no_app_cleaner)

      assert_equal 1, messages.count, messages
      assert_nil messages.first.call_site
    end
  end

  describe "entries with no application code behind them" do
    it "records no call site for a Sidekiq job's start and completion" do
      job_logger = RailsSemanticLogger::Sidekiq::JobLogger.new({})
      messages   = with_call_sites do
        semantic_logger_events { job_logger.call({"jid" => "123", "class" => "SimpleJob"}, "default") { nil } }
      end

      assert_equal ["Start #perform", "Completed #perform"], messages.map(&:message)
      messages.each { |message| assert_nil message.call_site, message.message }
    end

    it "records no call site for Sidekiq's error handler" do
      messages = with_call_sites do
        semantic_logger_events do
          RailsSemanticLogger::Sidekiq::Defaults::ERROR_HANDLER.call(
            RuntimeError.new("boom"), {context: "Job raised exception", job: {"class" => "SimpleJob"}}
          )
        end
      end

      assert_equal 1, messages.count, messages
      assert_nil messages.first.call_site
      refute messages.first.payload.key?(:call_site), messages.first.payload
    end

    it "records no call site for Solid Queue's events" do
      event = ActiveSupport::Notifications::Event.new(
        "claim.solid_queue", 5.seconds.ago, Time.zone.now, SecureRandom.uuid,
        {process_id: 42, job_ids: [1], claimed_job_ids: [1], size: 1}
      )
      messages = with_call_sites do
        semantic_logger_events { RailsSemanticLogger::SolidQueue::LogSubscriber.new.claim(event) }
      end

      assert_equal 1, messages.count, messages
      assert_nil messages.first.call_site
    end
  end
end

class CallSiteRequestTest < ActionDispatch::IntegrationTest
  include CallSiteTestHelpers

  # Rails' own backtrace cleaner, as an application has, which keeps the dummy application's frames,
  # such as its controllers. Rails also counts this file, under test/, as application code, so this
  # cleaner silences it, as if the request came from the app server.
  def rails_cleaner
    Rails::BacktraceCleaner.new.tap { |cleaner| cleaner.add_silencer { |line| line.include?(File.basename(__FILE__)) } }
  end

  def request_entries(&block)
    skip "Rails does not clean backtraces when BACKTRACE is set" if ENV["BACKTRACE"]

    with_call_sites do
      with_cleaner(rails_cleaner,
                   RailsSemanticLogger::ActionController::LogSubscriber,
                   RailsSemanticLogger::ActionView::LogSubscriber) do
        semantic_logger_events(&block)
      end
    end
  end

  def controller_file
    Rails.root.join("app/controllers/articles_controller.rb").to_s
  end

  # Returns the line in the controller of the first line that includes the text.
  def controller_line(text)
    File.readlines(controller_file).index { |line| line.include?(text) } + 1
  end

  def entry(messages, message)
    messages.find do |log|
      log.message.start_with?(message)
    end || flunk("No #{message} entry in #{messages.map(&:message)}")
  end

  describe "a request" do
    it "records the action for Processing and Completed" do
      messages = request_entries { get article_url(:new) }

      %w[Processing Completed].each do |message|
        log = entry(messages, message)

        assert_equal [controller_file, line_of(ArticlesController, :new)], call_site(log), message
        assert_equal "ArticlesController#new", log.call_site.label
      end
    end

    it "records no call site for Started" do
      messages = request_entries { get article_url(:new) }

      assert_nil entry(messages, "Started").call_site
    end

    it "records no call site for a template that Rails renders once the action has returned" do
      messages = request_entries { get article_url(:new) }

      assert_nil entry(messages, "Rendered").call_site
    end

    it "records the redirect_to call in the action" do
      messages = request_entries { get redirector_articles_url }

      assert_equal [controller_file, controller_line("redirect_to article_url(:new)")],
                   call_site(entry(messages, "Redirected to"))
    end

    it "records the send_data call in the action" do
      messages = request_entries { get download_data_articles_url }

      assert_equal [controller_file, controller_line("send_data")], call_site(entry(messages, "Sent data"))
    end

    it "records the permit call for unpermitted parameters" do
      messages = request_entries { get filtered_articles_url(title: "Title", other: "x") }

      assert_equal [controller_file, controller_line("params.permit")], call_site(entry(messages, "Unpermitted"))
    end

    it "records no call site for a template rendered once the action has returned, inside an around_action" do
      messages = request_entries { get "/welcome/index" }

      assert_nil entry(messages, "Rendered").call_site
    end

    it "records no call site for a halted filter chain, whose event names no controller" do
      messages = request_entries { get halted_articles_url }

      assert_nil entry(messages, "Filter chain halted").call_site
    end
  end
end
