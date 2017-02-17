require 'spec_helper'

module VCAP::CloudController::Jobs
  RSpec.describe Enqueuer do
    describe '#enqueue' do
      let(:wrapped_job) { Runtime::ModelDeletion.new('one', 'two') }
      let(:opts) { { queue: 'my-queue' } }
      let(:request_id) { 'abc123' }

      it 'delegates to Delayed::Job' do
        expect(Delayed::Job).to receive(:enqueue) do |enqueued_job, opts|
          expect(enqueued_job).to be_a ExceptionCatchingJob
          expect(enqueued_job.handler).to be_a RequestJob
          expect(enqueued_job.handler.job).to be_a TimeoutJob
          expect(enqueued_job.handler.job.job).to be wrapped_job
        end
        Enqueuer.new(wrapped_job, opts).enqueue
      end

      it "populates RequestJob's ID with the one from the thread-local Request" do
        expect(Delayed::Job).to receive(:enqueue) do |enqueued_job, opts|
          request_job = enqueued_job.handler
          expect(request_job.request_id).to eq request_id
        end

        ::VCAP::Request.current_id = request_id
        Enqueuer.new(wrapped_job, opts).enqueue
      end
    end

    describe '#run_inline' do
      let(:wrapped_job) { Runtime::ModelDeletion.new('one', 'two') }
      let(:opts) { {} }

      it 'schedules the job to run immediately in-process' do
        expect(Delayed::Job).to receive(:enqueue) do
          expect(Delayed::Worker.delay_jobs).to be(false)
        end

        expect(Delayed::Worker.delay_jobs).to be(true)
        Enqueuer.new(wrapped_job, opts).run_inline
        expect(Delayed::Worker.delay_jobs).to be(true)
      end

      context 'when executing the job fails' do
        it 'still restores delay_jobs flag' do
          expect(Delayed::Job).to receive(:enqueue).and_raise('Boom!')
          expect(Delayed::Worker.delay_jobs).to be(true)
          expect {
            Enqueuer.new(wrapped_job, opts).run_inline
          }.to raise_error /Boom!/
          expect(Delayed::Worker.delay_jobs).to be(true)
        end
      end
    end
  end
end
