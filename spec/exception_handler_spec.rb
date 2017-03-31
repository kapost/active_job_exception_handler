# frozen_string_literal: true

require "rails_helper"
require "climate_control"

RSpec.describe ExceptionHandler do
  subject do
    described_class.new exception_context: exception_context,
                        exception_processors: exception_processors,
                        rescue_retryable_errors: rescue_retryable_errors,
                        logger: tagged_logger
  end

  let(:source) { instance_spy ApplicationJob }
  let(:newsroom_id) { an_object_id }
  let(:external_site_id) { an_object_id }
  let(:processor_1) { instance_spy ExceptionHandlerStatsdProcessor }
  let(:processor_2) { instance_spy ExceptionHandlerStatsdProcessor }
  let(:exception_processors) { [processor_1, processor_2] }
  let(:exception_context) do
    ExceptionContext.new(source: source,
                         newsroom_id: newsroom_id,
                         external_site_id: external_site_id)
  end
  let(:rescue_retryable_errors) { false }

  let(:string_io) { StringIO.new }
  let(:tagged_logger) { ActiveSupport::TaggedLogging.new ActiveSupport::Logger.new(string_io) }

  describe "#add" do
    it "adds an ignorable error" do
      subject.add NoMethodError, :ignorables
      expect(subject.ignorables).to contain_exactly(NoMethodError)
    end

    it "adds a retryable error" do
      subject.add NoMethodError, :retryables
      expect(subject.retryables).to contain_exactly(Timeout::Error,
                                                    Net::HTTPError,
                                                    Errno::ECONNREFUSED,
                                                    NoMethodError)
    end

    it "adds an unretryable error" do
      subject.add NoMethodError, :unretryables
      expect(subject.unretryables).to contain_exactly(NoMethodError)
    end
  end

  describe "#process!" do
    TestUnknownError = Class.new(StandardError)

    shared_examples_for "an ignorable error" do
      before do
        subject.add ArgumentError, :ignorables
        subject.process! { fail ArgumentError }
      end

      it "calls exception processors" do
        expect(processor_1).to have_received(:process).with(ArgumentError, :ignorables, exception_context)
        expect(processor_2).to have_received(:process).with(ArgumentError, :ignorables, exception_context)
      end

      it "captures error" do
        expect(subject.error).to be_kind_of(ArgumentError)
      end

      it "marks as errored" do
        expect(subject.error?).to eq(true)
      end
    end

    shared_examples_for "a retryable error" do
      before do
        result = -> { subject.process! { fail Timeout::Error } }
        if rescue_retryable_errors
          result.call
        else
          expect(&result).to raise_error ExceptionHandler::RetryableError
        end
      end

      it "calls exception processors" do
        expect(processor_1).to have_received(:process).with(Timeout::Error, :retryables, exception_context)
        expect(processor_2).to have_received(:process).with(Timeout::Error, :retryables, exception_context)
      end

      it "captures error" do
        expect(subject.error).to be_kind_of(Timeout::Error)
      end

      it "marks as errored" do
        expect(subject.error?).to eq(true)
      end
    end

    shared_examples_for "an unretryable error" do
      before do
        subject.add NoMethodError, :unretryables
        subject.process! { fail NoMethodError }
      end

      it "calls exception processors" do
        expect(processor_1).to have_received(:process).with(NoMethodError, :unretryables, exception_context)
        expect(processor_2).to have_received(:process).with(NoMethodError, :unretryables, exception_context)
      end

      it "captures error" do
        expect(subject.error).to be_kind_of(NoMethodError)
      end

      it "marks as errored" do
        expect(subject.error?).to eq(true)
      end
    end

    shared_examples_for "an unknown error" do
      before do
        result = -> { subject.process! { fail TestUnknownError } }
        expect(&result).to raise_error TestUnknownError
      end

      it "calls exception processors" do
        expect(processor_1).to have_received(:process).with(TestUnknownError, :unknown, exception_context)
        expect(processor_2).to have_received(:process).with(TestUnknownError, :unknown, exception_context)
      end

      it "captures error" do
        expect(subject.error).to be_kind_of(TestUnknownError)
      end

      it "marks as errored" do
        expect(subject.error?).to eq(true)
      end
    end

    context "an ApplicationJob" do
      ExceptionHandlerTestJob = Class.new(AnalyticsJob)
      let(:source) { ExceptionHandlerTestJob.new }

      it_behaves_like "an ignorable error"
      it_behaves_like "a retryable error"
      it_behaves_like "an unretryable error"
      it_behaves_like "an unknown error"
    end

    context "an AnalyticsCollector" do
      let(:rescue_retryable_errors) { true }

      ExceptionHandlerTestCollector = Class.new(AnalyticsCollector)

      let(:source) { ExceptionHandlerTestCollector.new adapter: {}, emitter: {} }

      it_behaves_like "an ignorable error", "collector"
      it_behaves_like "a retryable error", "collector"
      it_behaves_like "an unretryable error", "collector"
      it_behaves_like "an unknown error", "collector"
    end

    context "exception processors" do
      context "ExceptionHandlerActionableFaultProcessor" do
        let(:exception_processors) { [ExceptionHandlerActionableFaultProcessor.new] }
        let(:error) { NoMethodError }
        let(:actionable_fault) do
          ActionableFault.find_by(newsroom_id: newsroom_id,
                                  external_site_id: external_site_id,
                                  error_name: error.name)
        end

        before do
          subject.add error, :unretryables
          subject.process! { fail error }
        end

        it "records actionable fault" do
          expect(ActionableFault.count).to eq(1)
          expect(actionable_fault.count).to eq(1)
        end
      end
    end

    context "logging exceptions" do
      let(:lines) { string_io.string.split("\n") }
      let(:error) do
        error = StandardError.new "This is a test"
        error.set_backtrace %w[/line1 /line2]
        error
      end

      context "when logging is disabled" do
        it "does not log errors" do
          action = -> { subject.process! { fail error } }

          ClimateControl.modify(DUMP_EXCEPTIONS: nil) do
            expect(&action).to raise_error StandardError
          end

          expect(lines).to be_empty
        end
      end

      context "when logging is enabled" do
        it "logs errors" do
          action = -> { subject.process! { fail error } }

          ClimateControl.modify(DUMP_EXCEPTIONS: "true") do
            expect(&action).to raise_error StandardError
          end

          expect(lines).to include "[ExceptionHandler] Caught unknown error: This is a test"
          expect(lines).to include "[ExceptionHandler] /line1"
          expect(lines).to include "/line2"
        end
      end
    end
  end
end
