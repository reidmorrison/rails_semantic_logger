class ArticlesController < ApplicationController
  def new
  end

  def create
    render plain: params[:article].inspect
  end

  def show
    raise ActiveRecord::RecordNotFound
  end
end
