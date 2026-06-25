class ArticlesController < ApplicationController
  class Handled < StandardError; end

  rescue_from Handled do
    render plain: "handled", status: :ok
  end

  def new
  end

  def create
    render plain: params[:article].inspect
  end

  def show
    raise ActiveRecord::RecordNotFound
  end

  def redirector
    redirect_to article_url(:new)
  end

  def rescued
    raise Handled, "boom"
  end

  def filtered
    permitted = params.permit(:title)
    render plain: permitted.inspect
  end
end
