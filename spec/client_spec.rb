require 'spec_helper'

RSpec.describe ActivePostgrest::Client do
  let(:stubs) { Faraday::Adapter::Test::Stubs.new }
  let(:conn) do
    Faraday.new do |f|
      f.request :json
      f.response :json
      f.adapter :test, stubs
    end
  end
  let(:client) { described_class.new('http://localhost:3000') }

  before do
    allow(Faraday).to receive(:new).and_call_original
  end

  describe '#initialize' do
    it 'stores base_url' do
      expect(client.base_url).to eq('http://localhost:3000')
    end
  end

  describe 'JWT auth header' do
    it 'sets Authorization header when jwt_token provided' do
      stubs.get('/users') { [200, {}, []] }
      authenticated = described_class.new('http://localhost:3000', 'my.jwt.token')
      # The header is set internally; we verify by checking the instance variable
      auth = authenticated.instance_variable_get(:@auth_header)
      expect(auth).to eq('Bearer my.jwt.token')
    end

    it 'sets no auth header without jwt_token' do
      auth = client.instance_variable_get(:@auth_header)
      expect(auth).to be_nil
    end
  end

  describe '#anonymous' do
    it 'returns a new client with the same base_url' do
      authenticated = described_class.new('http://localhost:3000', 'my.jwt.token')
      anon = authenticated.anonymous
      expect(anon.base_url).to eq('http://localhost:3000')
    end

    it 'returns a client with no auth header' do
      authenticated = described_class.new('http://localhost:3000', 'my.jwt.token')
      anon = authenticated.anonymous
      expect(anon.instance_variable_get(:@auth_header)).to be_nil
    end

    it 'does not mutate the original client' do
      authenticated = described_class.new('http://localhost:3000', 'my.jwt.token')
      authenticated.anonymous
      expect(authenticated.instance_variable_get(:@auth_header)).to eq('Bearer my.jwt.token')
    end
  end

  describe '#with_token' do
    it 'returns a new client with the same base_url' do
      result = client.with_token('new.jwt.token')
      expect(result.base_url).to eq('http://localhost:3000')
    end

    it 'sets Authorization header with the given token' do
      result = client.with_token('new.jwt.token')
      expect(result.instance_variable_get(:@auth_header)).to eq('Bearer new.jwt.token')
    end

    it 'replaces an existing token' do
      authenticated = described_class.new('http://localhost:3000', 'old.token')
      result = authenticated.with_token('new.token')
      expect(result.instance_variable_get(:@auth_header)).to eq('Bearer new.token')
    end

    it 'does not mutate the original client' do
      authenticated = described_class.new('http://localhost:3000', 'old.token')
      authenticated.with_token('new.token')
      expect(authenticated.instance_variable_get(:@auth_header)).to eq('Bearer old.token')
    end
  end

  describe '#tables' do
    it 'extracts table names from OpenAPI paths' do
      openapi = { 'paths' => { '/users' => {}, '/posts' => {}, '/' => {} } }
      allow(client).to receive(:openapi).and_return(openapi)
      expect(client.tables).to contain_exactly('users', 'posts')
    end

    it 'returns empty array when no paths' do
      allow(client).to receive(:openapi).and_return({})
      expect(client.tables).to eq([])
    end
  end

  describe '#table_schema' do
    it 'returns schema for a table' do
      openapi = { 'definitions' => { 'users' => { 'properties' => { 'id' => {} } } } }
      allow(client).to receive(:openapi).and_return(openapi)
      expect(client.table_schema('users')).to include('properties')
    end

    it 'returns empty hash for unknown table' do
      allow(client).to receive(:openapi).and_return({ 'definitions' => {} })
      expect(client.table_schema('ghost')).to eq({})
    end
  end

  describe '#get error handling' do
    def client_with_stub(status, body = {})
      stubs = Faraday::Adapter::Test::Stubs.new
      stubs.get('/users') { [status, {}, body] }
      test_conn = Faraday.new do |f|
        f.request :json
        f.response :json
        f.adapter :test, stubs
      end
      described_class.new('http://localhost:3000').tap do |c|
        c.instance_variable_set(:@conn, test_conn)
      end
    end

    {
      400 => ActivePostgrest::BadRequest,
      401 => ActivePostgrest::Unauthorized,
      403 => ActivePostgrest::Forbidden,
      404 => ActivePostgrest::ResourceNotFound,
      409 => ActivePostgrest::Conflict,
      422 => ActivePostgrest::UnprocessableEntity,
      500 => ActivePostgrest::ServerError,
      503 => ActivePostgrest::ServerError
    }.each do |status, klass|
      it "raises #{klass.name.split('::').last} on HTTP #{status}" do
        expect { client_with_stub(status).get('users') }.to raise_error(klass)
      end
    end

    it 'does not raise on HTTP 200' do
      expect { client_with_stub(200, []).get('users') }.not_to raise_error
    end

    it 'populates error attributes from response body' do
      body = { 'code' => '23505', 'message' => 'unique violation', 'details' => 'Key exists.', 'hint' => nil }
      expect { client_with_stub(409, body).get('users') }
        .to raise_error(ActivePostgrest::Conflict) { |e|
          expect(e.code).to        eq('23505')
          expect(e.message).to     eq('unique violation')
          expect(e.details).to     eq('Key exists.')
          expect(e.http_status).to eq(409)
        }
    end
  end
end
