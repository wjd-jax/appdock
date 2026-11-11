module Distribution
  class BaseController < ApplicationController
    layout 'distribution'
    before_action :authenticate_user!, unless: :trusted_lan?
  end
end
