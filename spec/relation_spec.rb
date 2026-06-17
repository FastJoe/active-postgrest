require 'spec_helper'

RSpec.describe ActivePostgrest::Relation do
  let(:client) { instance_double(ActivePostgrest::Client, base_url: 'http://localhost:3000') }
  let(:model_class) do
    Class.new(ActivePostgrest::Base) do
      def self.name = 'Widget'
      def self.primary_key = 'id'
    end
  end
  let(:relation) { described_class.new('widgets', client, model_class) }

  # ──────────────────────────────────────────────────────────────────────────
  # to_url helper — lets us check params without HTTP calls
  # ──────────────────────────────────────────────────────────────────────────

  def url_params(rel)
    uri = URI.parse(rel.to_url)
    uri.query ? URI.decode_www_form(uri.query).to_h : {}
  end

  def url_pairs(rel)
    uri = URI.parse(rel.to_url)
    uri.query ? URI.decode_www_form(uri.query) : []
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Basic URL construction
  # ──────────────────────────────────────────────────────────────────────────

  describe '#to_url' do
    it 'returns base URL with table when no params' do
      expect(relation.to_url).to eq('http://localhost:3000/widgets')
    end

    it 'appends query string when params present' do
      expect(relation.limit(5).to_url).to include('limit=5')
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Immutability — each builder method returns a new relation
  # ──────────────────────────────────────────────────────────────────────────

  describe 'immutability' do
    it 'does not mutate the original relation' do
      chained = relation.where(name: 'Alice')
      expect(relation.to_url).to eq('http://localhost:3000/widgets')
      expect(chained.to_url).to include('name=')
    end

    it 'chaining multiple where calls accumulates filters independently' do
      r1 = relation.where(active: true)
      r2 = r1.where(role: 'admin')
      expect(url_pairs(r1)).not_to include(['role', 'eq.admin'])
      expect(url_pairs(r2)).to include(['active', 'is.true'])
      expect(url_pairs(r2)).to include(['role', 'eq.admin'])
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # where — filter encoding
  # ──────────────────────────────────────────────────────────────────────────

  describe '#where' do
    it 'encodes string equality' do
      expect(url_pairs(relation.where(name: 'John'))).to include(['name', 'eq.John'])
    end

    it 'encodes nil as is.null' do
      expect(url_pairs(relation.where(deleted_at: nil))).to include(['deleted_at', 'is.null'])
    end

    it 'encodes true as is.true' do
      expect(url_pairs(relation.where(active: true))).to include(['active', 'is.true'])
    end

    it 'encodes false as is.false' do
      expect(url_pairs(relation.where(active: false))).to include(['active', 'is.false'])
    end

    it 'encodes array as in.(...)' do
      expect(url_pairs(relation.where(id: [1, 2, 3]))).to include(['id', 'in.(1,2,3)'])
    end

    it 'encodes inclusive range as gte+lte (two params with same key)' do
      pairs = url_pairs(relation.where(age: 18..30))
      expect(pairs).to include(['age', 'gte.18'])
      expect(pairs).to include(['age', 'lte.30'])
    end

    it 'encodes exclusive range with lt for end' do
      pairs = url_pairs(relation.where(age: 18...30))
      expect(pairs).to include(['age', 'gte.18'])
      expect(pairs).to include(['age', 'lt.30'])
    end

    it 'encodes hash as operator string' do
      expect(url_pairs(relation.where(age: { gt: 18 }))).to include(['age', 'gt.18'])
    end

    it 'encodes multi-op hash as multiple params' do
      pairs = url_pairs(relation.where(age: { gt: 18, lt: 65 }))
      expect(pairs).to include(['age', 'gt.18'])
      expect(pairs).to include(['age', 'lt.65'])
    end

    it 'returns a WhereChain when called with no args' do
      expect(relation.where).to be_a(ActivePostgrest::Relation::WhereChain)
    end

    context 'with table hash (AR-style joins filter)' do
      it 'expands table.column filters' do
        pairs = url_pairs(relation.where(companies: { name: 'Acme' }))
        expect(pairs).to include(['companies.name', 'eq.Acme'])
      end

      it 'supports multiple columns' do
        pairs = url_pairs(relation.where(companies: { active: true, name: 'Acme' }))
        expect(pairs).to include(['companies.active', 'is.true'])
        expect(pairs).to include(['companies.name', 'eq.Acme'])
      end

      it 'does not treat operator hashes as table filters' do
        pairs = url_pairs(relation.where(age: { gt: 18 }))
        expect(pairs).to include(['age', 'gt.18'])
        expect(pairs).not_to include(['age.gt', anything])
      end
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # where.not
  # ──────────────────────────────────────────────────────────────────────────

  describe '#where.not' do
    it 'negates equality' do
      expect(url_pairs(relation.where.not(name: 'John'))).to include(['name', 'not.eq.John'])
    end

    it 'negates nil check' do
      expect(url_pairs(relation.where.not(deleted_at: nil))).to include(['deleted_at', 'not.is.null'])
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # not_where
  # ──────────────────────────────────────────────────────────────────────────

  describe '#not_where' do
    it 'negates filters' do
      expect(url_pairs(relation.not_where(status: 'banned'))).to include(['status', 'not.eq.banned'])
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # or_where / and_where
  # ──────────────────────────────────────────────────────────────────────────

  describe '#or_where' do
    it 'builds or= param' do
      r = relation.or_where([{ age: { lt: 18 } }, { status: 'active' }])
      pairs = url_pairs(r)
      expect(pairs.assoc('or')[1]).to match(/age\.lt\.18/)
      expect(pairs.assoc('or')[1]).to match(/status\.eq\.active/)
    end
  end

  describe '#and_where' do
    it 'builds and= param' do
      r = relation.and_where([{ age: { gt: 18 } }, { status: 'active' }])
      pairs = url_pairs(r)
      expect(pairs.assoc('and')[1]).to match(/age\.gt\.18/)
      expect(pairs.assoc('and')[1]).to match(/status\.eq\.active/)
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # limit / offset / order / reorder
  # ──────────────────────────────────────────────────────────────────────────

  describe '#limit' do
    it 'adds limit param' do
      expect(url_params(relation.limit(10))).to include('limit' => '10')
    end
  end

  describe '#offset' do
    it 'adds offset param' do
      expect(url_params(relation.offset(20))).to include('offset' => '20')
    end
  end

  describe '#order' do
    it 'adds order param with direction' do
      expect(url_params(relation.order(:name, :asc))).to include('order' => 'name.asc')
    end

    it 'defaults direction to asc' do
      expect(url_params(relation.order(:name))).to include('order' => 'name.asc')
    end

    it 'appends nullslast' do
      expect(url_params(relation.order(:name, :asc, nulls: :last))).to include('order' => 'name.asc.nullslast')
    end

    it 'appends nullsfirst' do
      expect(url_params(relation.order(:name, :desc, nulls: :first))).to include('order' => 'name.desc.nullsfirst')
    end
  end

  describe '#reorder' do
    it 'replaces existing order' do
      r = relation.order(:name, :asc).reorder(:id, :desc)
      expect(url_params(r)).to include('order' => 'id.desc')
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # select
  # ──────────────────────────────────────────────────────────────────────────

  describe '#select' do
    it 'adds select param' do
      expect(url_params(relation.select(:id, :name))).to include('select' => 'id,name')
    end
  end

  describe '#spread' do
    it 'adds spread notation for a single table' do
      expect(url_params(relation.spread(:companies))).to include('select' => '...companies')
    end

    it 'adds spread notation for multiple tables' do
      params = url_params(relation.spread(:companies, :profiles))
      expect(params['select']).to include('...companies')
      expect(params['select']).to include('...profiles')
    end

    it 'composes with select' do
      params = url_params(relation.select(:id, :name).spread(:companies))
      expect(params['select']).to eq('id,name,...companies')
    end

    it 'does not mutate the original relation' do
      relation.spread(:companies)
      expect(url_params(relation)).not_to include('select')
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # joins / embed
  # ──────────────────────────────────────────────────────────────────────────

  describe '#joins' do
    it 'adds !inner hint (INNER JOIN semantics)' do
      r = relation.joins(:companies)
      expect(url_params(r)['select']).to include('companies!inner(*)')
    end

    it 'respects select option' do
      r = relation.joins(:companies, select: %w[id name])
      expect(url_params(r)['select']).to include('companies!inner(id,name)')
    end

    it 'supports aliased joins with foreign key' do
      r = relation.joins(:users, as: :mother, foreign_key: :mother_id)
      expect(url_params(r)['select']).to include('mother:users!mother_id!inner(*)')
    end

    it 'encodes join-level where filter as table.col param' do
      r = relation.joins(:companies, where: { name: 'Acme' })
      expect(url_pairs(r)).to include(['companies.name', 'eq.Acme'])
    end
  end

  describe '#left_joins' do
    it 'adds no !inner hint (LEFT JOIN semantics)' do
      r = relation.left_joins(:companies)
      select = url_params(r)['select']
      expect(select).to include('companies(*)')
      expect(select).not_to include('!inner')
    end

    it 'respects select option' do
      r = relation.left_joins(:companies, select: %w[id name])
      expect(url_params(r)['select']).to include('companies(id,name)')
    end
  end

  describe '#embed' do
    it 'adds embedded resource to select' do
      r = relation.embed(:company)
      expect(url_params(r)['select']).to include('company(*)')
    end

    it 'respects fields option' do
      r = relation.embed(:company, fields: %w[id name])
      expect(url_params(r)['select']).to include('company(id,name)')
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # none
  # ──────────────────────────────────────────────────────────────────────────

  describe '#none' do
    it 'returns empty array from to_a without HTTP call' do
      expect(relation.none.to_a).to eq([])
    end
  end

  describe '#anonymous' do
    it 'returns a new relation' do
      allow(client).to receive(:anonymous).and_return(instance_double(ActivePostgrest::Client, base_url: 'http://localhost:3000'))
      expect(relation.anonymous).not_to equal(relation)
    end

    it 'uses a client without auth header' do
      anon_client = instance_double(ActivePostgrest::Client, base_url: 'http://localhost:3000')
      allow(client).to receive(:anonymous).and_return(anon_client)
      expect(relation.anonymous.instance_variable_get(:@client)).to eq(anon_client)
    end

    it 'does not mutate the original relation' do
      allow(client).to receive(:anonymous).and_return(instance_double(ActivePostgrest::Client, base_url: 'http://localhost:3000'))
      relation.anonymous
      expect(relation.instance_variable_get(:@client)).to eq(client)
    end
  end

  describe '#with_token' do
    it 'returns a new relation' do
      allow(client).to receive(:with_token).and_return(instance_double(ActivePostgrest::Client, base_url: 'http://localhost:3000'))
      expect(relation.with_token('jwt')).not_to equal(relation)
    end

    it 'uses a client with the given token' do
      token_client = instance_double(ActivePostgrest::Client, base_url: 'http://localhost:3000')
      allow(client).to receive(:with_token).with('user.jwt').and_return(token_client)
      expect(relation.with_token('user.jwt').instance_variable_get(:@client)).to eq(token_client)
    end

    it 'does not mutate the original relation' do
      allow(client).to receive(:with_token).and_return(instance_double(ActivePostgrest::Client, base_url: 'http://localhost:3000'))
      relation.with_token('jwt')
      expect(relation.instance_variable_get(:@client)).to eq(client)
    end
  end

  describe '#with_schema' do
    it 'returns a new relation' do
      expect(relation.with_schema('private')).not_to equal(relation)
    end

    it 'stores the schema name' do
      expect(relation.with_schema('private').instance_variable_get(:@schema)).to eq('private')
    end

    it 'passes schema to client on to_a' do
      response = instance_double(Faraday::Response, body: [])
      expect(client).to receive(:get).with(anything, anything, hash_including(schema: 'private')).and_return(response)
      relation.with_schema('private').to_a
    end

    it 'passes schema to client on count' do
      response = instance_double(Faraday::Response, headers: { 'content-range' => '0-9/10' })
      expect(client).to receive(:get).with(anything, anything, hash_including(schema: 'private')).and_return(response)
      relation.with_schema('private').count
    end

    it 'does not mutate the original relation' do
      relation.with_schema('private')
      expect(relation.instance_variable_get(:@schema)).to be_nil
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # to_a / first / last / count — with stubbed client
  # ──────────────────────────────────────────────────────────────────────────

  describe '#to_a' do
    let(:response) { instance_double(Faraday::Response, body: [{ 'id' => 1, 'name' => 'Alice' }]) }

    before { allow(client).to receive(:get).and_return(response) }

    it 'returns model instances' do
      result = relation.to_a
      expect(result).to all(be_a(model_class))
      expect(result.first['name']).to eq('Alice')
    end
  end

  describe '#first' do
    let(:response) { instance_double(Faraday::Response, body: [{ 'id' => 1 }]) }

    before { allow(client).to receive(:get).and_return(response) }

    it 'limits to 1 and returns single record' do
      result = relation.first
      expect(result).to be_a(model_class)
      expect(client).to have_received(:get).with('widgets', hash_including(limit: 1), schema: nil)
    end
  end

  describe '#last' do
    let(:response) { instance_double(Faraday::Response, body: [{ 'id' => 99 }]) }

    before { allow(client).to receive(:get).and_return(response) }

    it 'orders by pk desc and limits to 1' do
      result = relation.last
      expect(result).to be_a(model_class)
      expect(client).to have_received(:get).with('widgets', hash_including(limit: 1, order: 'id.desc'), schema: nil)
    end
  end

  describe '#count' do
    let(:response) { instance_double(Faraday::Response, headers: { 'content-range' => '0-24/42' }) }

    before { allow(client).to receive(:get).and_return(response) }

    it 'parses content-range header' do
      expect(relation.count).to eq(42)
    end

    it 'returns 0 for none relation' do
      expect(relation.none.count).to eq(0)
    end

    it 'sends count=exact by default' do
      expect(client).to receive(:get).with(anything, anything, count: :exact, schema: nil).and_return(response)
      relation.count
    end

    it 'sends count=planned when requested' do
      planned = instance_double(Faraday::Response, headers: { 'content-range' => '0-24/~1050' })
      expect(client).to receive(:get).with(anything, anything, count: :planned, schema: nil).and_return(planned)
      expect(relation.count(:planned)).to eq(1050)
    end

    it 'sends count=estimated when requested' do
      estimated = instance_double(Faraday::Response, headers: { 'content-range' => '0-24/~950' })
      expect(client).to receive(:get).with(anything, anything, count: :estimated, schema: nil).and_return(estimated)
      expect(relation.count(:estimated)).to eq(950)
    end

    it 'strips tilde prefix from approximate counts' do
      approx = instance_double(Faraday::Response, headers: { 'content-range' => '0-24/~5000' })
      allow(client).to receive(:get).and_return(approx)
      expect(relation.count(:planned)).to eq(5000)
    end
  end

  describe '#exists?' do
    context 'when records exist' do
      let(:response) { instance_double(Faraday::Response, headers: { 'content-range' => '0-9/5' }) }

      before { allow(client).to receive(:get).and_return(response) }

      it 'returns true' do
        expect(relation.exists?).to be true
      end
    end

    context 'when no records' do
      let(:response) { instance_double(Faraday::Response, headers: { 'content-range' => '*/0' }) }

      before { allow(client).to receive(:get).and_return(response) }

      it 'returns false' do
        expect(relation.exists?).to be false
      end
    end

    it 'returns false for none relation without HTTP call' do
      expect(relation.none.exists?).to be false
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # aggregate methods
  # ──────────────────────────────────────────────────────────────────────────

  describe 'aggregate methods' do
    let(:response) { instance_double(Faraday::Response, body: [{ 'avg' => '32.4' }]) }

    before { allow(client).to receive(:get).and_return(response) }

    it '#average sends select=age.avg() and returns the value' do
      expect(relation.average(:age)).to eq('32.4')
      expect(client).to have_received(:get).with('widgets', hash_including(select: 'age.avg()'), schema: nil)
    end

    it '#sum sends select=amount.sum()' do
      allow(client).to receive(:get).and_return(instance_double(Faraday::Response, body: [{ 'sum' => '1000' }]))
      expect(relation.sum(:amount)).to eq('1000')
      expect(client).to have_received(:get).with('widgets', hash_including(select: 'amount.sum()'), schema: nil)
    end

    it '#minimum sends select=age.min()' do
      allow(client).to receive(:get).and_return(instance_double(Faraday::Response, body: [{ 'min' => '18' }]))
      expect(relation.minimum(:age)).to eq('18')
    end

    it '#maximum sends select=age.max()' do
      allow(client).to receive(:get).and_return(instance_double(Faraday::Response, body: [{ 'max' => '75' }]))
      expect(relation.maximum(:age)).to eq('75')
    end

    it 'respects existing where filters' do
      expect(relation.where(active: true).average(:age)).to eq('32.4')
      expect(client).to have_received(:get).with('widgets', hash_including('active' => 'is.true'), schema: nil)
    end

    it 'returns nil for none relation without HTTP call' do
      expect(relation.none.average(:age)).to be_nil
    end
  end

  describe '#pluck' do
    let(:response) do
      instance_double(Faraday::Response, body: [{ 'id' => 1, 'name' => 'Alice' }, { 'id' => 2, 'name' => 'Bob' }])
    end

    before { allow(client).to receive(:get).and_return(response) }

    it 'returns single column values' do
      expect(relation.pluck(:name)).to eq(%w[Alice Bob])
    end

    it 'returns tuples for multiple columns' do
      expect(relation.pluck(:id, :name)).to eq([[1, 'Alice'], [2, 'Bob']])
    end
  end

  describe '#pick' do
    let(:response) { instance_double(Faraday::Response, body: [{ 'name' => 'Alice' }]) }

    before { allow(client).to receive(:get).and_return(response) }

    it 'returns first plucked value' do
      expect(relation.pick(:name)).to eq('Alice')
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # method_missing delegates to model scopes
  # ──────────────────────────────────────────────────────────────────────────

  describe '#method_missing' do
    before do
      model_class.instance_variable_set(:@connection, client)
      model_class.scope(:active, -> { model_class.where(active: true) })
    end

    it 'delegates named scopes' do
      r = relation.active
      expect(url_pairs(r)).to include(['active', 'is.true'])
    end

    it 'raises NoMethodError for unknown methods' do
      expect { relation.nonexistent_scope }.to raise_error(NoMethodError)
    end
  end
end
