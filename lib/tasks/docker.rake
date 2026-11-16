# frozen_string_literal: true

namespace :docker do
  task build: :environment do
    system('docker build -t appdock:dev .')
  end
end
