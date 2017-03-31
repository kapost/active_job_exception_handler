# frozen_string_literal: true

class ExceptionHandler
  RetryableError = Class.new(StandardError)

  TYPES = %i[ignorables retryables unretryables].freeze

  attr_reader(*TYPES)
  attr_reader :error

  def initialize(exception_context:,
                 rescue_retryable_errors:,
                 exception_processors: [ExceptionHandlerStatsdProcessor.new,
                                        ExceptionHandlerActionableFaultProcessor.new],
                 logger: ActiveSupport::TaggedLogging.new(Logger.new(STDOUT)))
    @exception_context = exception_context
    @exception_processors = exception_processors
    @rescue_retryable_errors = rescue_retryable_errors
    @logger = logger
    @error = nil
    @ignorables = []
    @retryables = [Timeout::Error, Net::HTTPError, Errno::ECONNREFUSED]
    @unretryables = []
  end

  def add(error, type)
    fail(StandardError, "Invalid error category: #{type}.") unless TYPES.include?(type)
    public_send(type) << error
  end

  def error?
    error.present?
  end

  def process!
    yield if block_given?

  rescue *ignorables => error
    handle_ignorable(error)

  rescue *retryables => error
    handle_retryable(error)

  rescue *unretryables => error
    handle_unretryable(error)

  rescue StandardError => error
    handle_unknown(error)
  end

  private

  attr_reader :exception_context, :logger, :rescue_retryable_errors, :exception_processors

  # Common actions that we want to perform for any type of error
  def common_actions(error, type)
    @error = error

    log error, type

    exception_processors.each do |processor|
      processor.process(error, type, exception_context)
    end
  end

  # Exceptions that we can't do anything about
  def handle_ignorable(error)
    common_actions(error, :ignorables)
  end

  # Transient exceptions that might go away upon a retry.
  # Raise `ExceptionHandler::RetryableError` so shoryuken will pick up the
  # job according to the retry intervals.
  # Configure honeybadger to ignore this exception in the initializer.
  #
  # NOTE: Retries only apply to ApplicationJobs and
  # don't have meaning for other objects like Collectors.
  def handle_retryable(error)
    common_actions(error, :retryables)

    fail RetryableError unless rescue_retryable_errors
  end

  # Exceptions that we can't do anything about, but want to be notified on.  This
  # category should include errors where we might want to notify the customer, so
  # they can take some action
  def handle_unretryable(error)
    common_actions(error, :unretryables)
  end

  # Unknown errors
  # - Instrument and bubble out
  def handle_unknown(error)
    common_actions(error, :unknown)

    fail error
  end

  def log(error, type)
    return unless ENV["DUMP_EXCEPTIONS"]

    logger.tagged self.class do |tagged_logger|
      tagged_logger.info "Caught #{type} error: #{error.message}"
      tagged_logger.info error.backtrace.join("\n")
    end
  end

  class ExceptionContext
    include Virtus.model
    include ActiveModel::Validations

    attribute :source, String
    attribute :queue, String
    attribute :args, Array

    validates :source, :queue, :args, presence: true
  end
end
