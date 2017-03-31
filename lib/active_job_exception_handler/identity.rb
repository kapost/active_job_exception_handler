# frozen_string_literal: true

module ActiveJobExceptionHandler
  # Gem identity information.
  module Identity
    def self.name
      "active_job_exception_handler"
    end

    def self.label
      "ActiveJobExceptionHandler"
    end

    def self.version
      "0.1.0"
    end

    def self.version_label
      "#{label} #{version}"
    end
  end
end
