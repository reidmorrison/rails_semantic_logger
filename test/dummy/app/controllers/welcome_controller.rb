class WelcomeController < ApplicationController
  # Wraps the action, as an around_action that sets the locale does, so that tests can check that it is
  # not taken for the code that rendered the action's template.
  around_action :wrap_action

  def index
  end

  private

  def wrap_action
    yield
  end
end
