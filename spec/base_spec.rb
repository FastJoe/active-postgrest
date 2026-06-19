require 'spec_helper'

RSpec.describe ActivePostgrest::Base do
  # ──────────────────────────────────────────────────────────────────────────
  # Test model definitions
  # ──────────────────────────────────────────────────────────────────────────

  let(:client) { instance_double(ActivePostgrest::Client, base_url: 'http://localhost:3000') }

  let(:post_class) do
    c = Class.new(described_class) do
      def self.name = 'Post'
    end
    c.instance_variable_set(:@connection, client)
    c
  end

  let(:comment_class) do
    c = Class.new(described_class) do
      def self.name = 'Comment'
    end
    c.instance_variable_set(:@connection, client)
    c
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Class-level configuration
  # ──────────────────────────────────────────────────────────────────────────

  describe '.table_name' do
    it 'infers from class name' do
      expect(post_class.table_name).to eq('posts')
    end

    it 'can be overridden' do
      post_class.table_name = 'blog_posts'
      expect(post_class.table_name).to eq('blog_posts')
    end
  end

  describe '.primary_key' do
    it 'defaults to id' do
      expect(post_class.primary_key).to eq('id')
    end

    it 'can be overridden' do
      post_class.primary_key = :uuid
      expect(post_class.primary_key).to eq('uuid')
    end
  end

  describe '.schema_name' do
    it 'is nil by default' do
      expect(post_class.schema_name).to be_nil
    end

    it 'can be set' do
      post_class.schema_name = 'private'
      expect(post_class.schema_name).to eq('private')
    end

    it 'inherits from superclass' do
      parent = Class.new(described_class)
      parent.schema_name = 'analytics'
      child = Class.new(parent)
      expect(child.schema_name).to eq('analytics')
    end

    it 'subclass can override parent schema' do
      parent = Class.new(described_class)
      parent.schema_name = 'analytics'
      child = Class.new(parent)
      child.schema_name = 'private'
      expect(child.schema_name).to eq('private')
      expect(parent.schema_name).to eq('analytics')
    end
  end

  describe '.with_schema' do
    let(:ok_response) { instance_double(Faraday::Response, body: [], headers: { 'content-range' => '*/0' }) }

    before { allow(client).to receive(:get).and_return(ok_response) }

    it 'returns a Relation with the schema set' do
      rel = post_class.with_schema('private')
      expect(rel).to be_a(ActivePostgrest::Relation)
      expect(rel.instance_variable_get(:@schema)).to eq('private')
    end
  end

  describe '.attribute / .attribute_types' do
    it 'registers type cast for attribute' do
      post_class.attribute(:published_at, :datetime)
      expect(post_class.attribute_types).to include('published_at' => :datetime)
    end

    it 'inherits parent attribute types' do
      parent = Class.new(described_class)
      parent.attribute(:created_at, :datetime)
      child = Class.new(parent)
      expect(child.attribute_types).to include('created_at' => :datetime)
    end

    it 'child can override parent attribute type' do
      parent = Class.new(described_class)
      parent.attribute(:score, :decimal)
      child = Class.new(parent)
      child.attribute(:score, :integer)
      expect(child.attribute_types['score']).to eq(:integer)
      expect(parent.attribute_types['score']).to eq(:decimal)
    end

    it 'child attributes do not leak to parent' do
      parent = Class.new(described_class)
      parent.attribute(:created_at, :datetime)
      child = Class.new(parent)
      child.attribute(:score, :integer)
      expect(parent.attribute_types).not_to include('score')
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Type casting on initialize
  # ──────────────────────────────────────────────────────────────────────────

  describe 'attribute type casting' do
    subject(:record) do
      post_class.new(
        'id' => 1,
        'published_at' => '2024-01-15T10:30:00Z',
        'score' => '3.14',
        'birth_date' => '1990-06-17',
        'title' => 'Hello'
      )
    end

    before do
      post_class.attribute(:published_at, :datetime)
      post_class.attribute(:score, :decimal)
      post_class.attribute(:birth_date, :date)
    end

    it 'casts datetime strings to Time' do
      expect(record.published_at).to be_a(Time)
    end

    it 'casts decimal strings to BigDecimal' do
      expect(record.score).to be_a(BigDecimal)
      expect(record.score).to eq(BigDecimal('3.14'))
    end

    it 'casts date strings to Date' do
      expect(record.birth_date).to be_a(Date)
      expect(record.birth_date).to eq(Date.new(1990, 6, 17))
    end

    it 'leaves untyped attributes as-is' do
      expect(record.title).to eq('Hello')
    end

    it 'handles nil without raising' do
      r = post_class.new('published_at' => nil)
      expect(r.published_at).to be_nil
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Instance accessors
  # ──────────────────────────────────────────────────────────────────────────

  describe 'instance interface' do
    subject(:record) { post_class.new('id' => 5, 'title' => 'Test') }

    it '#[] returns attribute by string key' do
      expect(record['title']).to eq('Test')
    end

    it '#[] returns attribute by symbol key' do
      expect(record[:title]).to eq('Test')
    end

    it '#attributes returns hash' do
      expect(record.attributes).to include('id' => 5, 'title' => 'Test')
    end

    it '#to_h returns same hash as attributes' do
      expect(record.to_h).to eq(record.attributes)
    end

    it 'method_missing exposes attributes as methods' do
      expect(record.title).to eq('Test')
    end

    it 'respond_to? returns true for attribute methods' do
      expect(record.respond_to?(:title)).to be(true)
    end

    it 'raises NoMethodError for unknown attributes' do
      expect { record.nonexistent }.to raise_error(NoMethodError)
    end

    context 'when a declared attribute is absent from the API response (e.g. after select)' do
      let(:klass) do
        Class.new(described_class) do
          def self.name = 'Widget'
          attribute :score, :integer
        end
      end
      let(:partial_record) { klass.new({ 'id' => 1 }, true, client) }

      it 'getter returns nil instead of raising NoMethodError' do
        expect(partial_record.score).to be_nil
      end

      it 'respond_to? returns true for the declared attribute' do
        expect(partial_record.respond_to?(:score)).to be true
      end

      it 'setter works even when the key was absent in the response' do
        partial_record.score = 42
        expect(partial_record.score).to eq(42)
      end
    end

    it '#inspect includes class name and attributes' do
      expect(record.inspect).to include('Post')
      expect(record.inspect).to include('title')
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Associations — belongs_to
  # ──────────────────────────────────────────────────────────────────────────

  describe '.belongs_to' do
    before do
      # Ensure comment_class is registered in ObjectSpace so constantize works
      stub_const('Post', post_class)
      stub_const('Comment', comment_class)
      comment_class.belongs_to(:post)
    end

    it 'defines an accessor that wraps the embedded hash' do
      # PostgREST embeds under table name "posts" (no alias)
      record = comment_class.new('posts' => { 'id' => 1, 'title' => 'Hi' })
      expect(record.post).to be_a(Post)
      expect(record.post.title).to eq('Hi')
    end

    it 'returns nil when association data is missing' do
      record = comment_class.new({})
      expect(record.post).to be_nil
    end

    it 'defines a with_* scope class method' do
      expect(comment_class).to respond_to(:with_post)
    end
  end

  describe '.belongs_to with class_name and foreign_key (self-referential)' do
    before do
      stub_const('User', Class.new(described_class) do
        def self.name = 'User'
      end)
      User.instance_variable_set(:@connection, client)
      User.belongs_to(:mother, class_name: 'User', foreign_key: :mother_id)
    end

    it 'reads the embedded data under the aliased key' do
      record = User.new('mother' => { 'id' => 10, 'first_name' => 'Jane' })
      expect(record.mother).to be_a(User)
      expect(record.mother.first_name).to eq('Jane')
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Associations — has_many
  # ──────────────────────────────────────────────────────────────────────────

  describe '.has_many' do
    before do
      stub_const('Post', post_class)
      stub_const('Comment', comment_class)
      post_class.has_many(:comments)
    end

    it 'returns array of associated model instances' do
      record = post_class.new('comments' => [{ 'id' => 1 }, { 'id' => 2 }])
      expect(record.comments).to all(be_a(Comment))
      expect(record.comments.length).to eq(2)
    end

    it 'returns empty array when no data' do
      record = post_class.new({})
      expect(record.comments).to eq([])
    end

    it 'defines a with_* scope class method' do
      expect(post_class).to respond_to(:with_comments)
    end

    it 'handles a single embedded object (non-array) returned by PostgREST' do
      record = post_class.new('comments' => { 'id' => 1 })
      expect(record.comments.length).to eq(1)
      expect(record.comments.first).to be_a(Comment)
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Associations — has_one
  # ──────────────────────────────────────────────────────────────────────────

  describe '.has_one' do
    before do
      stub_const('Post', post_class)
      stub_const('Comment', comment_class)
      post_class.has_one(:comment)
    end

    it 'returns single instance' do
      record = post_class.new('comment' => { 'id' => 7 })
      expect(record.comment).to be_a(Comment)
      expect(record.comment['id']).to eq(7)
    end

    it 'returns nil when absent' do
      record = post_class.new({})
      expect(record.comment).to be_nil
    end

    it 'defines a with_* scope class method' do
      expect(post_class).to respond_to(:with_comment)
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Query class methods (delegate to relation)
  # ──────────────────────────────────────────────────────────────────────────

  describe 'query delegation' do
    let(:ok_response) { instance_double(Faraday::Response, body: [], headers: { 'content-range' => '*/0' }) }

    before { allow(client).to receive(:get).and_return(ok_response) }

    it '.all returns a Relation' do
      expect(post_class.all).to be_a(ActivePostgrest::Relation)
    end

    it '.none returns an empty Relation' do
      expect(post_class.none.to_a).to eq([])
    end

    it '.where returns a Relation' do
      expect(post_class.where(id: 1)).to be_a(ActivePostgrest::Relation)
    end

    it '.limit returns a Relation' do
      expect(post_class.limit(5)).to be_a(ActivePostgrest::Relation)
    end

    it '.order returns a Relation' do
      expect(post_class.order(:id)).to be_a(ActivePostgrest::Relation)
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # find / find! / find_by / find_by!
  # ──────────────────────────────────────────────────────────────────────────

  describe '.find and .find_by' do
    let(:found_response) { instance_double(Faraday::Response, body: [{ 'id' => 1, 'title' => 'Found' }]) }
    let(:empty_response) { instance_double(Faraday::Response, body: []) }

    it '.find returns record when found' do
      allow(client).to receive(:get).and_return(found_response)
      record = post_class.find(1)
      expect(record).to be_a(post_class)
    end

    it '.find returns nil when not found' do
      allow(client).to receive(:get).and_return(empty_response)
      expect(post_class.find(999)).to be_nil
    end

    it '.find! raises RecordNotFound when missing' do
      allow(client).to receive(:get).and_return(empty_response)
      expect { post_class.find!(999) }.to raise_error(ActivePostgrest::RecordNotFound)
    end

    it '.find_by! raises RecordNotFound when missing' do
      allow(client).to receive(:get).and_return(empty_response)
      expect { post_class.find_by!(title: 'Ghost') }.to raise_error(ActivePostgrest::RecordNotFound)
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # scope
  # ──────────────────────────────────────────────────────────────────────────

  describe '.scope' do
    before do
      post_class.scope(:published, -> { post_class.where(published: true) })
    end

    it 'defines a class method that returns a Relation' do
      expect(post_class.published).to be_a(ActivePostgrest::Relation)
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # POSTGRES_TYPE_CAST constant
  # ──────────────────────────────────────────────────────────────────────────

  describe 'POSTGRES_TYPE_CAST' do
    it 'maps timestamp with time zone to :datetime' do
      expect(described_class::POSTGRES_TYPE_CAST['timestamp with time zone']).to eq(:datetime)
    end

    it 'maps numeric to :decimal' do
      expect(described_class::POSTGRES_TYPE_CAST['numeric']).to eq(:decimal)
    end

    it 'maps date to :date' do
      expect(described_class::POSTGRES_TYPE_CAST['date']).to eq(:date)
    end
  end
end
