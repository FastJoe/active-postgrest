require 'spec_helper'

RSpec.describe ActivePostgrest::Error do
  def build_response(status:, body:)
    instance_double(Faraday::Response, status: status, body: body)
  end

  describe 'attributes' do
    subject(:error) do
      described_class.new(build_response(
                            status: 422,
                            body: {
                              'code' => '23505',
                              'message' => 'duplicate key value violates unique constraint',
                              'details' => 'Key (email)=(x@y.com) already exists.',
                              'hint' => 'Change the email.'
                            }
                          ))
    end

    it { expect(error.message).to     eq('duplicate key value violates unique constraint') }
    it { expect(error.code).to        eq('23505') }
    it { expect(error.details).to     eq('Key (email)=(x@y.com) already exists.') }
    it { expect(error.hint).to        eq('Change the email.') }
    it { expect(error.http_status).to eq(422) }
  end

  describe 'fallback message' do
    it "uses 'HTTP <status>' when body has no message" do
      error = described_class.new(build_response(status: 503, body: {}))
      expect(error.message).to eq('HTTP 503')
    end
  end

  describe 'non-hash body' do
    it 'does not raise when body is a string' do
      expect do
        described_class.new(build_response(status: 500, body: 'Internal Server Error'))
      end.not_to raise_error
    end
  end

  describe 'subclasses' do
    [
      ActivePostgrest::BadRequest,
      ActivePostgrest::Unauthorized,
      ActivePostgrest::Forbidden,
      ActivePostgrest::ResourceNotFound,
      ActivePostgrest::Conflict,
      ActivePostgrest::UnprocessableEntity,
      ActivePostgrest::ServerError
    ].each do |klass|
      it "#{klass.name.split('::').last} inherits from Error" do
        expect(klass.superclass).to eq(described_class)
      end
    end
  end
end
