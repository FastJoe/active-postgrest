require 'spec_helper'

RSpec.describe 'mutations' do
  let(:client) { instance_double(ActivePostgrest::Client, base_url: 'http://localhost:3000') }

  let(:model_class) do
    c = Class.new(ActivePostgrest::Base) do
      def self.name = 'Widget'
      def self.primary_key = 'id'
    end
    c.instance_variable_set(:@connection, client)
    c
  end

  let(:relation) { ActivePostgrest::Relation.new('widgets', client, model_class) }

  def ok_response(body)
    instance_double(Faraday::Response, body: body, status: 200)
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Client
  # ──────────────────────────────────────────────────────────────────────────

  describe ActivePostgrest::Client do
    subject(:http) { described_class.new('http://pg') }

    let(:conn) { instance_double(Faraday::Connection) }

    before { http.instance_variable_set(:@conn, conn) }

    shared_examples 'raises on error' do |method, *call_args|
      it 'raises on 409' do
        resp = instance_double(Faraday::Response, status: 409, body: { 'message' => 'conflict' })
        allow(conn).to receive(method).and_yield(double('req', headers: {}, params: {})).and_return(resp)
        expect { http.public_send(method, *call_args) }.to raise_error(ActivePostgrest::Conflict)
      end
    end

    describe '#post' do
      it 'sends POST with Prefer header' do
        req = double('req', headers: {})
        expect(conn).to receive(:post).with('widgets', { name: 'Foo' }).and_yield(req).and_return(ok_response([]))
        http.post('widgets', { name: 'Foo' }, prefer: 'return=representation')
        expect(req.headers['Prefer']).to eq('return=representation')
      end
    end

    describe '#patch' do
      it 'sends PATCH with filters as params and Prefer header' do
        req = double('req', headers: {}, params: {})
        expect(conn).to receive(:patch).with('widgets', { name: 'Bar' }).and_yield(req).and_return(ok_response([]))
        http.patch('widgets', { id: 'eq.1' }, { name: 'Bar' }, prefer: 'return=representation')
        expect(req.headers['Prefer']).to eq('return=representation')
        expect(req.params).to include(id: 'eq.1')
      end
    end

    describe '#delete' do
      it 'sends DELETE with filters as params and Prefer header' do
        req = double('req', headers: {}, params: {})
        expect(conn).to receive(:delete).with('widgets').and_yield(req).and_return(ok_response([]))
        http.delete('widgets', { id: 'eq.1' }, prefer: 'return=representation')
        expect(req.headers['Prefer']).to eq('return=representation')
        expect(req.params).to include(id: 'eq.1')
      end
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Relation
  # ──────────────────────────────────────────────────────────────────────────

  describe ActivePostgrest::Relation do
    describe '#insert' do
      it 'posts attrs and returns a persisted record' do
        allow(client).to receive(:post)
          .with('widgets', { name: 'X' }, prefer: 'return=representation', schema: nil)
          .and_return(ok_response([{ 'id' => 1, 'name' => 'X' }]))

        record = relation.insert({ name: 'X' })
        expect(record).to be_a(model_class)
        expect(record.id).to eq(1)
        expect(record).to be_persisted
      end

      it 'returns nil when PostgREST returns empty body' do
        allow(client).to receive(:post).and_return(ok_response(nil))
        expect(relation.insert({ name: 'X' })).to be_nil
      end
    end

    describe '#insert_all' do
      it 'posts array and returns persisted records' do
        allow(client).to receive(:post)
          .with('widgets', [{ name: 'A' }, { name: 'B' }], prefer: 'return=representation', schema: nil)
          .and_return(ok_response([{ 'id' => 1, 'name' => 'A' }, { 'id' => 2, 'name' => 'B' }]))

        records = relation.insert_all([{ name: 'A' }, { name: 'B' }])
        expect(records.map(&:name)).to eq(%w[A B])
      end
    end

    describe '#upsert' do
      it 'posts with merge-duplicates prefer header' do
        expect(client).to receive(:post)
          .with('widgets', { id: 1, name: 'X' },
                prefer: 'return=representation,resolution=merge-duplicates',
                schema: nil)
          .and_return(ok_response([{ 'id' => 1, 'name' => 'X' }]))

        relation.upsert({ id: 1, name: 'X' })
      end
    end

    describe '#update_all' do
      it 'patches with current filters and returns updated records' do
        filtered = relation.where(active: true)
        expect(client).to receive(:patch)
          .with('widgets', hash_including('active' => 'is.true'), { name: 'Y' },
                prefer: 'return=representation', schema: nil)
          .and_return(ok_response([{ 'id' => 1, 'name' => 'Y' }]))

        records = filtered.update_all({ name: 'Y' })
        expect(records.first.name).to eq('Y')
      end
    end

    describe '#delete_all' do
      it 'deletes with current filters and returns deleted records' do
        filtered = relation.where(id: 42)
        expect(client).to receive(:delete)
          .with('widgets', hash_including('id' => 'eq.42'),
                prefer: 'return=representation', schema: nil)
          .and_return(ok_response([{ 'id' => 42, 'name' => 'Gone' }]))

        records = filtered.delete_all
        expect(records.first.id).to eq(42)
      end
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Base — persistence state
  # ──────────────────────────────────────────────────────────────────────────

  describe ActivePostgrest::Base do
    describe '#new_record? / #persisted?' do
      it 'new_record? is true for Base.new' do
        expect(model_class.new(id: 1)).to be_new_record
      end

      it 'persisted? is true for records from DB' do
        record = model_class.new({ 'id' => 1 }, true)
        expect(record).to be_persisted
      end
    end

    describe 'setters via method_missing' do
      it 'sets a known attribute' do
        record = model_class.new('name' => 'Old')
        record.name = 'New'
        expect(record.name).to eq('New')
      end

      it 'raises NoMethodError for unknown attribute' do
        record = model_class.new
        expect { record.unknown = 'x' }.to raise_error(NoMethodError)
      end
    end

    describe '.create' do
      it 'calls insert and returns a persisted record' do
        allow(client).to receive(:post)
          .and_return(ok_response([{ 'id' => 5, 'name' => 'Widget' }]))

        record = model_class.create({ name: 'Widget' })
        expect(record).to be_persisted
        expect(record.id).to eq(5)
      end
    end

    describe '#save (new record)' do
      it 'inserts and marks as persisted' do
        record = model_class.new('name' => 'Fresh')
        allow(client).to receive(:post)
          .and_return(ok_response([{ 'id' => 7, 'name' => 'Fresh' }]))

        result = record.save
        expect(result).to be true
        expect(record).to be_persisted
        expect(record.id).to eq(7)
      end
    end

    describe '#save (persisted record)' do
      it 'patches by primary key' do
        record = model_class.new({ 'id' => 3, 'name' => 'Old' }, true)
        allow(client).to receive(:patch)
          .and_return(ok_response([{ 'id' => 3, 'name' => 'Old' }]))

        expect(record.save).to be true
      end
    end

    describe '#update' do
      it 'merges attrs and saves' do
        record = model_class.new({ 'id' => 3, 'name' => 'Old' }, true)
        allow(client).to receive(:patch)
          .and_return(ok_response([{ 'id' => 3, 'name' => 'New' }]))

        record.update({ 'name' => 'New' })
        expect(record.name).to eq('New')
      end
    end

    describe '#destroy' do
      it 'deletes by PK and marks as destroyed' do
        record = model_class.new({ 'id' => 3 }, true)
        allow(client).to receive(:delete).and_return(ok_response([{ 'id' => 3 }]))

        record.destroy
        expect(record).to be_destroyed
        expect(record).not_to be_persisted
        expect(record).not_to be_new_record
      end

      it 'raises ArgumentError when primary key is nil' do
        record = model_class.new('name' => 'x')
        expect { record.destroy }.to raise_error(ArgumentError, /primary key/)
      end

      it 'prevents re-insert via save after destroy' do
        record = model_class.new({ 'id' => 3 }, true)
        allow(client).to receive(:delete).and_return(ok_response([{ 'id' => 3 }]))
        record.destroy
        expect(record.save).to be false
      end
    end

    describe '#save (persisted) uses stored client' do
      it 'issues PATCH through the client the record was loaded with' do
        other_client = instance_double(ActivePostgrest::Client, base_url: 'http://other')
        record = model_class.new({ 'id' => 1, 'name' => 'X' }, true, other_client)
        expect(other_client).to receive(:patch)
          .with('widgets', anything, anything,
                prefer: 'return=representation', schema: nil)
          .and_return(ok_response([{ 'id' => 1, 'name' => 'X' }]))
        record.save
      end
    end

    describe '#save (persisted) with embedded associations' do
      it 'excludes Hash and Array attributes from the PATCH body' do
        record = model_class.new({ 'id' => 1, 'name' => 'X', 'company' => { 'id' => 2 } }, true)
        expect(client).to receive(:patch)
          .with('widgets', anything,
                satisfy { |body| !body.key?('company') && body.key?('name') },
                prefer: 'return=representation', schema: nil)
          .and_return(ok_response([{ 'id' => 1, 'name' => 'X' }]))
        record.save
      end
    end

    describe '#save (persisted) with nil primary key' do
      it 'raises ArgumentError' do
        record = model_class.new('name' => 'x', 'id' => nil)
        record.instance_variable_set(:@new_record, false)
        expect { record.save }.to raise_error(ArgumentError, /primary key/)
      end
    end

    describe 'setter type casting via method_missing' do
      before { model_class.attribute(:count, :integer) }

      it 'casts value on setter when attribute type is declared' do
        record = model_class.new('count' => 1)
        record.count = '42'
        expect(record.count).to be_a(Integer)
        expect(record.count).to eq(42)
      end
    end

    describe '#[]= type casting' do
      before { model_class.attribute(:score, :decimal) }

      it 'casts value via []= when attribute type is declared' do
        record = model_class.new('score' => 1.0)
        record['score'] = '3.14'
        expect(record['score']).to be_a(BigDecimal)
      end
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Relation — create / create!
  # ──────────────────────────────────────────────────────────────────────────

  describe ActivePostgrest::Relation, 'write shortcuts' do
    describe '#create' do
      it 'inserts and returns a persisted record' do
        allow(client).to receive(:post)
          .and_return(ok_response([{ 'id' => 9, 'name' => 'Widget' }]))
        record = relation.create({ name: 'Widget' })
        expect(record).to be_persisted
        expect(record.id).to eq(9)
      end

      it 'returns nil when PostgREST returns empty body' do
        allow(client).to receive(:post).and_return(ok_response(nil))
        expect(relation.create({ name: 'Widget' })).to be_nil
      end
    end

    describe '#create!' do
      it 'raises RecordNotSaved when body is empty' do
        allow(client).to receive(:post).and_return(ok_response(nil))
        expect { relation.create!({ name: 'Widget' }) }.to raise_error(ActivePostgrest::RecordNotSaved)
      end
    end
  end
end
