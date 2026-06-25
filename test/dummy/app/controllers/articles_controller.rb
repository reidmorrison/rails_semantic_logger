class ArticlesController < ApplicationController
  class Handled < StandardError; end

  rescue_from Handled do
    render plain: "handled", status: :ok
  end

  before_action :halt_chain, only: :halted

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

  def halted
    render plain: "should not be reached"
  end

  def download_data
    send_data "hello world", filename: "greeting.txt"
  end

  def download_file
    send_file Rails.root.join("public", "favicon.ico").to_s, disposition: :inline
  end

  def upload
    render plain: params[:file].class.name
  end

  private

  def halt_chain
    redirect_to article_url(:new)
  end
end
