# frozen_string_literal: true
# Compatibility aliases only; new automation uses appdock:*.
Rake::Task.tasks.select { |task| task.name.start_with?('appdock:') }.each do |target|
  task target.name.sub('appdock:', 'zealot:') => target.name
end
