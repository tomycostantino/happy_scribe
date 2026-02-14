# Agentic AI Features Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add AI-powered meeting analysis (summaries, action items, embeddings, knowledge graph) and an agentic chat interface where users can ask questions across their entire meeting history using RubyLLM tools.

**Architecture:** Three increments built bottom-up. Increment 1 creates the data models and background jobs that process transcripts through AI. Increment 2 wraps each capability as a `RubyLLM::Tool` for composability. Increment 3 wires up RubyLLM's `acts_as_chat` Rails integration with all tools attached, giving users an agentic chat that can search transcripts, query the knowledge graph, look up meetings, and draft follow-ups.

**Tech Stack:** Rails 8.1, RubyLLM v1.11.0 (OpenAI + Anthropic), pgvector via `neighbor` gem, Solid Queue, Turbo Streams, Minitest.

---

## Current State

Already built and working:
- `User`, `Meeting`, `Transcript`, `TranscriptSegment` models
- HappyScribe transcription pipeline (SubmitJob -> StatusPollJob -> ExportFetchJob)
- `Meeting::Transcribable`, `Meeting::Recordable`, `Transcript::Parseable`, `Transcript::Formattable` concerns
- `ruby_llm` configured with OpenAI + Anthropic keys (`config/initializers/ruby_llm.rb`)
- `neighbor` gem + pgvector extension enabled in PostgreSQL
- Authentication, Active Storage, Action Text, Solid Queue

Not yet built:
- `Summary`, `ActionItem`, `TranscriptChunk` models (designed in spec/01 but not created)
- AI processing jobs (designed in spec/04 and spec/05 but not implemented)
- Knowledge graph models, RubyLLM tools, agentic chat — all new

---

## Increment 1: Foundation (Data Layer + AI Jobs)

### Task 1: New data models — Summary, ActionItem, TranscriptChunk

**Files:**
- Create: `db/migrate/TIMESTAMP_create_summaries.rb`
- Create: `db/migrate/TIMESTAMP_create_action_items.rb`
- Create: `db/migrate/TIMESTAMP_create_transcript_chunks.rb`
- Create: `app/models/summary.rb`
- Create: `app/models/action_item.rb`
- Create: `app/models/transcript_chunk.rb`
- Modify: `app/models/meeting.rb` (add associations, uncomment `check_processing_complete!`)
- Modify: `app/models/transcript.rb` (add `has_many :transcript_chunks`)
- Create: `test/models/summary_test.rb`
- Create: `test/models/action_item_test.rb`
- Create: `test/models/transcript_chunk_test.rb`
- Create: `test/fixtures/summaries.yml`
- Create: `test/fixtures/action_items.yml`
- Create: `test/fixtures/transcript_chunks.yml`

**Step 1: Write failing tests for Summary**

```ruby
# test/models/summary_test.rb
require "test_helper"

class SummaryTest < ActiveSupport::TestCase
  test "valid summary" do
    summary = Summary.new(meeting: meetings(:one), model_used: "claude-sonnet-4-20250514")
    summary.content = "This meeting covered project updates."
    assert summary.valid?
  end

  test "requires a meeting" do
    summary = Summary.new(model_used: "claude-sonnet-4-20250514")
    summary.content = "Some text"
    assert_not summary.valid?
  end

  test "belongs to meeting" do
    summary = summaries(:one)
    assert_instance_of Meeting, summary.meeting
  end

  test "stores rich text content via Action Text" do
    summary = Summary.create!(meeting: meetings(:two), model_used: "test")
    summary.update!(content: "<h2>Summary</h2><p>The team discussed progress.</p>")
    assert summary.content.present?
  end
end
```

**Step 2: Write failing tests for ActionItem**

```ruby
# test/models/action_item_test.rb
require "test_helper"

class ActionItemTest < ActiveSupport::TestCase
  test "valid action item" do
    item = ActionItem.new(meeting: meetings(:one), description: "Send the Q3 report")
    assert item.valid?
  end

  test "requires description" do
    item = ActionItem.new(meeting: meetings(:one))
    assert_not item.valid?
    assert_includes item.errors[:description], "can't be blank"
  end

  test "requires a meeting" do
    item = ActionItem.new(description: "Do something")
    assert_not item.valid?
  end

  test "defaults completed to false" do
    item = ActionItem.new
    assert_equal false, item.completed
  end

  test "scopes: pending and done" do
    meeting = meetings(:one)
    pending_item = meeting.action_items.create!(description: "Pending task", completed: false)
    done_item = meeting.action_items.create!(description: "Done task", completed: true)

    assert_includes ActionItem.pending, pending_item
    assert_not_includes ActionItem.pending, done_item
    assert_includes ActionItem.done, done_item
  end
end
```

**Step 3: Write failing tests for TranscriptChunk**

```ruby
# test/models/transcript_chunk_test.rb
require "test_helper"

class TranscriptChunkTest < ActiveSupport::TestCase
  test "valid chunk" do
    chunk = TranscriptChunk.new(transcript: transcripts(:one), content: "Speaker 1: Hello.", position: 0)
    assert chunk.valid?
  end

  test "requires content" do
    chunk = TranscriptChunk.new(transcript: transcripts(:one), position: 0)
    assert_not chunk.valid?
    assert_includes chunk.errors[:content], "can't be blank"
  end

  test "requires position" do
    chunk = TranscriptChunk.new(transcript: transcripts(:one), content: "Some text")
    assert_not chunk.valid?
    assert_includes chunk.errors[:position], "can't be blank"
  end

  test "requires a transcript" do
    chunk = TranscriptChunk.new(content: "Some text", position: 0)
    assert_not chunk.valid?
  end

  test "has_neighbors for embedding" do
    assert TranscriptChunk.method_defined?(:nearest_neighbors)
  end
end
```

**Step 4: Run tests to verify they fail**

Run: `bin/rails test test/models/summary_test.rb test/models/action_item_test.rb test/models/transcript_chunk_test.rb`
Expected: FAIL (models don't exist yet)

**Step 5: Create migrations**

```ruby
# db/migrate/TIMESTAMP_create_summaries.rb
class CreateSummaries < ActiveRecord::Migration[8.1]
  def change
    create_table :summaries do |t|
      t.references :meeting, null: false, foreign_key: true
      t.string :model_used

      t.timestamps
    end

    add_index :summaries, :meeting_id, unique: true
  end
end
```

```ruby
# db/migrate/TIMESTAMP_create_action_items.rb
class CreateActionItems < ActiveRecord::Migration[8.1]
  def change
    create_table :action_items do |t|
      t.references :meeting, null: false, foreign_key: true
      t.text :description, null: false
      t.string :assignee
      t.date :due_date
      t.boolean :completed, null: false, default: false

      t.timestamps
    end

    add_index :action_items, [:meeting_id, :completed]
  end
end
```

```ruby
# db/migrate/TIMESTAMP_create_transcript_chunks.rb
class CreateTranscriptChunks < ActiveRecord::Migration[8.1]
  def change
    create_table :transcript_chunks do |t|
      t.references :transcript, null: false, foreign_key: true
      t.text :content, null: false
      t.vector :embedding, limit: 1536
      t.integer :position, null: false
      t.float :start_time
      t.float :end_time

      t.timestamps
    end

    add_index :transcript_chunks, [:transcript_id, :position]
  end
end
```

**Step 6: Create models**

```ruby
# app/models/summary.rb
class Summary < ApplicationRecord
  belongs_to :meeting

  has_rich_text :content
end
```

```ruby
# app/models/action_item.rb
class ActionItem < ApplicationRecord
  belongs_to :meeting

  validates :description, presence: true

  scope :pending, -> { where(completed: false) }
  scope :done, -> { where(completed: true) }
end
```

```ruby
# app/models/transcript_chunk.rb
class TranscriptChunk < ApplicationRecord
  belongs_to :transcript

  has_neighbors :embedding

  validates :content, presence: true
  validates :position, presence: true
end
```

**Step 7: Update existing models**

```ruby
# app/models/meeting.rb — add associations, uncomment check_processing_complete!
class Meeting < ApplicationRecord
  include Recordable
  include Transcribable

  belongs_to :user
  has_one :summary, dependent: :destroy
  has_many :action_items, dependent: :destroy

  enum :status, {
    uploading: "uploading",
    transcribing: "transcribing",
    transcribed: "transcribed",
    processing: "processing",
    completed: "completed",
    failed: "failed"
  }, default: :uploading

  validates :title, presence: true
  validates :language, presence: true

  def check_processing_complete!
    return unless summary.present? && action_items.any?
    update!(status: :completed)
  end
end
```

```ruby
# app/models/transcript.rb — add has_many :transcript_chunks
class Transcript < ApplicationRecord
  include Parseable
  include Formattable

  belongs_to :meeting
  has_many :transcript_segments, dependent: :destroy
  has_many :transcript_chunks, dependent: :destroy

  has_rich_text :content

  enum :status, {
    pending: "pending",
    processing: "processing",
    completed: "completed",
    failed: "failed"
  }, default: :pending
end
```

**Step 8: Create fixtures**

```yaml
# test/fixtures/summaries.yml
one:
  meeting: one
  model_used: "claude-sonnet-4-20250514"
```

```yaml
# test/fixtures/action_items.yml
one:
  meeting: one
  description: "Send the Q3 report to the finance team"
  assignee: "Sarah"
  completed: false

two:
  meeting: one
  description: "Schedule follow-up meeting for next week"
  assignee: "Tom"
  due_date: "2026-02-19"
  completed: false
```

```yaml
# test/fixtures/transcript_chunks.yml
one:
  transcript: one
  content: "Speaker 1 [00:00:00]: Hello everyone.\n\nSpeaker 2 [00:00:03]: Thanks."
  position: 0
  start_time: 0.0
  end_time: 8.2
```

**Step 9: Run migration and tests**

Run: `bin/rails db:migrate && bin/rails test test/models/summary_test.rb test/models/action_item_test.rb test/models/transcript_chunk_test.rb`
Expected: All tests PASS

**Step 10: Commit**

```bash
git add -A && git commit -m "feat: add Summary, ActionItem, TranscriptChunk models with migrations"
```

---

### Task 2: Knowledge graph models — KnowledgeEntity, KnowledgeRelationship, KnowledgeEntityMention

**Files:**
- Create: `db/migrate/TIMESTAMP_create_knowledge_entities.rb`
- Create: `db/migrate/TIMESTAMP_create_knowledge_relationships.rb`
- Create: `db/migrate/TIMESTAMP_create_knowledge_entity_mentions.rb`
- Create: `app/models/knowledge_entity.rb`
- Create: `app/models/knowledge_relationship.rb`
- Create: `app/models/knowledge_entity_mention.rb`
- Modify: `app/models/user.rb` (add `has_many :knowledge_entities`)
- Modify: `app/models/meeting.rb` (add knowledge graph associations)
- Create: `test/models/knowledge_entity_test.rb`
- Create: `test/models/knowledge_relationship_test.rb`
- Create: `test/models/knowledge_entity_mention_test.rb`
- Create: `test/fixtures/knowledge_entities.yml`
- Create: `test/fixtures/knowledge_relationships.yml`
- Create: `test/fixtures/knowledge_entity_mentions.yml`

**Step 1: Write failing tests**

```ruby
# test/models/knowledge_entity_test.rb
require "test_helper"

class KnowledgeEntityTest < ActiveSupport::TestCase
  test "valid entity" do
    entity = KnowledgeEntity.new(
      user: users(:one),
      name: "API Redesign",
      entity_type: "topic"
    )
    assert entity.valid?
  end

  test "requires name" do
    entity = KnowledgeEntity.new(user: users(:one), entity_type: "topic")
    assert_not entity.valid?
    assert_includes entity.errors[:name], "can't be blank"
  end

  test "requires entity_type" do
    entity = KnowledgeEntity.new(user: users(:one), name: "Test")
    assert_not entity.valid?
    assert_includes entity.errors[:entity_type], "can't be blank"
  end

  test "requires user" do
    entity = KnowledgeEntity.new(name: "Test", entity_type: "topic")
    assert_not entity.valid?
  end

  test "entity_type must be valid" do
    entity = KnowledgeEntity.new(user: users(:one), name: "Test", entity_type: "invalid_type")
    assert_not entity.valid?
  end

  test "name is unique within user and entity_type" do
    KnowledgeEntity.create!(user: users(:one), name: "API Redesign", entity_type: "topic")
    duplicate = KnowledgeEntity.new(user: users(:one), name: "API Redesign", entity_type: "topic")
    assert_not duplicate.valid?
  end

  test "same name allowed for different entity_types" do
    KnowledgeEntity.create!(user: users(:one), name: "Ruby", entity_type: "technology")
    different_type = KnowledgeEntity.new(user: users(:one), name: "Ruby", entity_type: "person")
    assert different_type.valid?
  end

  test "same name allowed for different users" do
    KnowledgeEntity.create!(user: users(:one), name: "API Redesign", entity_type: "topic")
    different_user = KnowledgeEntity.new(user: users(:two), name: "API Redesign", entity_type: "topic")
    assert different_user.valid?
  end

  test "has_neighbors for embedding" do
    assert KnowledgeEntity.method_defined?(:nearest_neighbors)
  end

  test "outgoing and incoming relationships" do
    entity_a = knowledge_entities(:api_redesign)
    entity_b = knowledge_entities(:alice)

    rel = KnowledgeRelationship.create!(
      source_entity: entity_a,
      target_entity: entity_b,
      meeting: meetings(:one),
      relationship_type: "discussed"
    )

    assert_includes entity_a.outgoing_relationships, rel
    assert_includes entity_b.incoming_relationships, rel
  end

  test "meetings through mentions" do
    entity = knowledge_entities(:api_redesign)
    KnowledgeEntityMention.create!(
      knowledge_entity: entity,
      meeting: meetings(:one),
      context: "We discussed the API redesign in detail."
    )

    assert_includes entity.meetings, meetings(:one)
  end
end
```

```ruby
# test/models/knowledge_relationship_test.rb
require "test_helper"

class KnowledgeRelationshipTest < ActiveSupport::TestCase
  test "valid relationship" do
    rel = KnowledgeRelationship.new(
      source_entity: knowledge_entities(:api_redesign),
      target_entity: knowledge_entities(:alice),
      meeting: meetings(:one),
      relationship_type: "discussed"
    )
    assert rel.valid?
  end

  test "requires source_entity" do
    rel = KnowledgeRelationship.new(
      target_entity: knowledge_entities(:alice),
      meeting: meetings(:one),
      relationship_type: "discussed"
    )
    assert_not rel.valid?
  end

  test "requires target_entity" do
    rel = KnowledgeRelationship.new(
      source_entity: knowledge_entities(:api_redesign),
      meeting: meetings(:one),
      relationship_type: "discussed"
    )
    assert_not rel.valid?
  end

  test "requires meeting" do
    rel = KnowledgeRelationship.new(
      source_entity: knowledge_entities(:api_redesign),
      target_entity: knowledge_entities(:alice),
      relationship_type: "discussed"
    )
    assert_not rel.valid?
  end

  test "requires relationship_type" do
    rel = KnowledgeRelationship.new(
      source_entity: knowledge_entities(:api_redesign),
      target_entity: knowledge_entities(:alice),
      meeting: meetings(:one)
    )
    assert_not rel.valid?
  end

  test "relationship_type must be valid" do
    rel = KnowledgeRelationship.new(
      source_entity: knowledge_entities(:api_redesign),
      target_entity: knowledge_entities(:alice),
      meeting: meetings(:one),
      relationship_type: "invalid"
    )
    assert_not rel.valid?
  end
end
```

```ruby
# test/models/knowledge_entity_mention_test.rb
require "test_helper"

class KnowledgeEntityMentionTest < ActiveSupport::TestCase
  test "valid mention" do
    mention = KnowledgeEntityMention.new(
      knowledge_entity: knowledge_entities(:api_redesign),
      meeting: meetings(:one),
      context: "We discussed the API redesign."
    )
    assert mention.valid?
  end

  test "requires knowledge_entity" do
    mention = KnowledgeEntityMention.new(meeting: meetings(:one))
    assert_not mention.valid?
  end

  test "requires meeting" do
    mention = KnowledgeEntityMention.new(knowledge_entity: knowledge_entities(:api_redesign))
    assert_not mention.valid?
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bin/rails test test/models/knowledge_entity_test.rb test/models/knowledge_relationship_test.rb test/models/knowledge_entity_mention_test.rb`
Expected: FAIL

**Step 3: Create migrations**

```ruby
# db/migrate/TIMESTAMP_create_knowledge_entities.rb
class CreateKnowledgeEntities < ActiveRecord::Migration[8.1]
  def change
    create_table :knowledge_entities do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.string :entity_type, null: false
      t.jsonb :properties, default: {}
      t.vector :embedding, limit: 1536
      t.integer :mention_count, null: false, default: 0

      t.timestamps
    end

    add_index :knowledge_entities, [:user_id, :name, :entity_type], unique: true
    add_index :knowledge_entities, [:user_id, :entity_type]
  end
end
```

```ruby
# db/migrate/TIMESTAMP_create_knowledge_relationships.rb
class CreateKnowledgeRelationships < ActiveRecord::Migration[8.1]
  def change
    create_table :knowledge_relationships do |t|
      t.references :source_entity, null: false, foreign_key: { to_table: :knowledge_entities }
      t.references :target_entity, null: false, foreign_key: { to_table: :knowledge_entities }
      t.references :meeting, null: false, foreign_key: true
      t.string :relationship_type, null: false
      t.jsonb :properties, default: {}
      t.float :weight, default: 1.0

      t.timestamps
    end

    add_index :knowledge_relationships,
              [:source_entity_id, :target_entity_id, :meeting_id, :relationship_type],
              unique: true, name: "idx_knowledge_relationships_unique"
  end
end
```

```ruby
# db/migrate/TIMESTAMP_create_knowledge_entity_mentions.rb
class CreateKnowledgeEntityMentions < ActiveRecord::Migration[8.1]
  def change
    create_table :knowledge_entity_mentions do |t|
      t.references :knowledge_entity, null: false, foreign_key: true
      t.references :meeting, null: false, foreign_key: true
      t.text :context

      t.timestamps
    end

    add_index :knowledge_entity_mentions,
              [:knowledge_entity_id, :meeting_id],
              unique: true, name: "idx_entity_mentions_unique"
  end
end
```

**Step 4: Create models**

```ruby
# app/models/knowledge_entity.rb
class KnowledgeEntity < ApplicationRecord
  ENTITY_TYPES = %w[person topic decision project technology action_item organization].freeze

  belongs_to :user
  has_many :outgoing_relationships, class_name: "KnowledgeRelationship",
           foreign_key: :source_entity_id, dependent: :destroy
  has_many :incoming_relationships, class_name: "KnowledgeRelationship",
           foreign_key: :target_entity_id, dependent: :destroy
  has_many :knowledge_entity_mentions, dependent: :destroy
  has_many :meetings, through: :knowledge_entity_mentions

  has_neighbors :embedding

  validates :name, presence: true
  validates :entity_type, presence: true, inclusion: { in: ENTITY_TYPES }
  validates :name, uniqueness: { scope: [:user_id, :entity_type] }
end
```

```ruby
# app/models/knowledge_relationship.rb
class KnowledgeRelationship < ApplicationRecord
  RELATIONSHIP_TYPES = %w[discussed decided assigned_to works_on mentioned_with depends_on followed_up].freeze

  belongs_to :source_entity, class_name: "KnowledgeEntity"
  belongs_to :target_entity, class_name: "KnowledgeEntity"
  belongs_to :meeting

  validates :relationship_type, presence: true, inclusion: { in: RELATIONSHIP_TYPES }
end
```

```ruby
# app/models/knowledge_entity_mention.rb
class KnowledgeEntityMention < ApplicationRecord
  belongs_to :knowledge_entity
  belongs_to :meeting
end
```

**Step 5: Update existing models**

Add to `app/models/user.rb`:
```ruby
has_many :knowledge_entities, dependent: :destroy
```

Add to `app/models/meeting.rb`:
```ruby
has_many :knowledge_entity_mentions, dependent: :destroy
has_many :knowledge_entities, through: :knowledge_entity_mentions
has_many :knowledge_relationships, dependent: :destroy
```

**Step 6: Create fixtures**

```yaml
# test/fixtures/knowledge_entities.yml
api_redesign:
  user: one
  name: "API Redesign"
  entity_type: "topic"
  mention_count: 3

alice:
  user: one
  name: "Alice"
  entity_type: "person"
  mention_count: 5

ruby_lang:
  user: one
  name: "Ruby"
  entity_type: "technology"
  mention_count: 2
```

```yaml
# test/fixtures/knowledge_relationships.yml
alice_works_on_api:
  source_entity: alice
  target_entity: api_redesign
  meeting: one
  relationship_type: "works_on"
  weight: 1.0
```

```yaml
# test/fixtures/knowledge_entity_mentions.yml
# (empty — created in tests as needed)
```

**Step 7: Also ensure a `users(:two)` fixture exists**

Check `test/fixtures/users.yml` — if only `one:` exists, add:
```yaml
two:
  email_address: "other@example.com"
  password_digest: <%= BCrypt::Password.create("password") %>
```

**Step 8: Run migration and tests**

Run: `bin/rails db:migrate && bin/rails test test/models/knowledge_entity_test.rb test/models/knowledge_relationship_test.rb test/models/knowledge_entity_mention_test.rb`
Expected: All tests PASS

**Step 9: Commit**

```bash
git add -A && git commit -m "feat: add knowledge graph models — KnowledgeEntity, KnowledgeRelationship, KnowledgeEntityMention"
```

---

### Task 3: AI configuration initializer

**Files:**
- Create: `config/initializers/ai.rb`

**Step 1: Create the initializer**

```ruby
# config/initializers/ai.rb
Rails.application.config.ai = ActiveSupport::OrderedOptions.new
Rails.application.config.ai.default_model = ENV.fetch("AI_MODEL", "claude-sonnet-4-20250514")
Rails.application.config.ai.embedding_model = ENV.fetch("AI_EMBEDDING_MODEL", "text-embedding-3-small")
```

**Step 2: Commit**

```bash
git add -A && git commit -m "feat: add AI model configuration initializer"
```

---

### Task 4: TranscriptChunker service

**Files:**
- Create: `app/services/transcript_chunker.rb`
- Create: `test/services/transcript_chunker_test.rb`

**Step 1: Write failing tests**

```ruby
# test/services/transcript_chunker_test.rb
require "test_helper"

class TranscriptChunkerTest < ActiveSupport::TestCase
  test "chunks transcript segments into groups respecting segment boundaries" do
    transcript = transcripts(:one)
    chunker = TranscriptChunker.new(transcript, max_tokens: 500)
    chunks = chunker.chunk

    assert_equal 1, chunks.length
    assert_includes chunks[0][:content], "Speaker 1"
    assert_includes chunks[0][:content], "Speaker 2"
    assert_in_delta 0.0, chunks[0][:start_time]
    assert_in_delta 11.0, chunks[0][:end_time]
    assert_equal 0, chunks[0][:position]
  end

  test "splits into multiple chunks when content exceeds max tokens" do
    transcript = transcripts(:two)

    20.times do |i|
      transcript.transcript_segments.create!(
        speaker: "Speaker #{i % 2 + 1}",
        content: "This is a longer segment number #{i} with enough content to contribute to the token count. " * 5,
        start_time: i * 10.0,
        end_time: (i + 1) * 10.0,
        position: i
      )
    end

    chunker = TranscriptChunker.new(transcript, max_tokens: 100)
    chunks = chunker.chunk

    assert chunks.length > 1

    chunks.each_with_index do |chunk, i|
      assert_equal i, chunk[:position]
      assert chunk[:content].present?
      assert_not_nil chunk[:start_time]
      assert_not_nil chunk[:end_time]
    end

    start_times = chunks.map { |c| c[:start_time] }
    assert_equal start_times, start_times.sort
  end

  test "includes overlap — last segment of previous chunk appears in next chunk" do
    transcript = transcripts(:two)

    10.times do |i|
      transcript.transcript_segments.create!(
        speaker: "Speaker 1",
        content: "Segment #{i}. " * 30,
        start_time: i * 10.0,
        end_time: (i + 1) * 10.0,
        position: i
      )
    end

    chunker = TranscriptChunker.new(transcript, max_tokens: 100)
    chunks = chunker.chunk

    if chunks.length > 1
      first_chunk_last_line = chunks[0][:content].split("\n\n").last
      second_chunk_first_line = chunks[1][:content].split("\n\n").first
      assert_equal first_chunk_last_line, second_chunk_first_line
    end
  end

  test "handles transcript with no segments" do
    transcript = transcripts(:two)
    chunker = TranscriptChunker.new(transcript)
    chunks = chunker.chunk
    assert_equal [], chunks
  end

  test "handles single segment" do
    transcript = transcripts(:two)
    transcript.transcript_segments.create!(
      speaker: "Speaker 1", content: "Just one segment.",
      start_time: 0.0, end_time: 3.0, position: 0
    )

    chunker = TranscriptChunker.new(transcript)
    chunks = chunker.chunk

    assert_equal 1, chunks.length
    assert_includes chunks[0][:content], "Just one segment."
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bin/rails test test/services/transcript_chunker_test.rb`
Expected: FAIL

**Step 3: Implement the chunker**

```ruby
# app/services/transcript_chunker.rb
class TranscriptChunker
  CHARS_PER_TOKEN = 4
  DEFAULT_MAX_TOKENS = 500

  def initialize(transcript, max_tokens: DEFAULT_MAX_TOKENS)
    @transcript = transcript
    @max_chars = max_tokens * CHARS_PER_TOKEN
  end

  def chunk
    segments = @transcript.transcript_segments.order(:position).to_a
    return [] if segments.empty?

    chunks = []
    current_segments = []
    current_chars = 0

    segments.each do |segment|
      formatted = format_segment(segment)
      segment_chars = formatted.length

      if current_chars + segment_chars > @max_chars && current_segments.any?
        chunks << build_chunk(current_segments, chunks.length)

        overlap = current_segments.last
        current_segments = overlap ? [overlap] : []
        current_chars = overlap ? format_segment(overlap).length : 0
      end

      current_segments << segment
      current_chars += segment_chars
    end

    chunks << build_chunk(current_segments, chunks.length) if current_segments.any?
    chunks
  end

  private

  def format_segment(segment)
    timestamp = format_timestamp(segment.start_time)
    "#{segment.speaker} [#{timestamp}]: #{segment.content}"
  end

  def format_timestamp(seconds)
    return "00:00:00" if seconds.nil?
    Time.at(seconds.to_f).utc.strftime("%H:%M:%S")
  end

  def build_chunk(segments, position)
    content = segments.map { |s| format_segment(s) }.join("\n\n")
    {
      content: content,
      start_time: segments.first.start_time,
      end_time: segments.last.end_time,
      position: position
    }
  end
end
```

**Step 4: Run tests**

Run: `bin/rails test test/services/transcript_chunker_test.rb`
Expected: All PASS

**Step 5: Commit**

```bash
git add -A && git commit -m "feat: add TranscriptChunker service for embedding preparation"
```

---

### Task 5: GenerateSummaryJob

Follows spec/04 design. See `spec/04_ai_processing.md` Task 3 for full test and implementation code.

**Files:**
- Create: `app/jobs/generate_summary_job.rb`
- Create: `test/jobs/generate_summary_job_test.rb`

**Step 1: Write failing tests** (see spec/04 Task 3 Step 1)

**Step 2: Run tests to verify they fail**

Run: `bin/rails test test/jobs/generate_summary_job_test.rb`
Expected: FAIL

**Step 3: Implement the job** (see spec/04 Task 3 Step 3)

Note: Use `meeting.transcript.formatted_text` (from `Transcript::Formattable` concern) for transcript text.

**Step 4: Run tests**

Run: `bin/rails test test/jobs/generate_summary_job_test.rb`
Expected: All PASS

**Step 5: Commit**

```bash
git add -A && git commit -m "feat: add GenerateSummaryJob with Claude Sonnet integration"
```

---

### Task 6: ExtractActionItemsJob

Follows spec/04 design. See `spec/04_ai_processing.md` Task 4 for full test and implementation code.

**Files:**
- Create: `app/jobs/extract_action_items_job.rb`
- Create: `test/jobs/extract_action_items_job_test.rb`

**Step 1-5:** Follow spec/04 Task 4 Steps 1-5.

**Step 6: Commit**

```bash
git add -A && git commit -m "feat: add ExtractActionItemsJob with structured JSON extraction"
```

---

### Task 7: GenerateEmbeddingsJob

Follows spec/05 design. See `spec/05_transcript_embeddings.md` Task 2 for full test and implementation code.

**Files:**
- Create: `app/jobs/generate_embeddings_job.rb`
- Create: `test/jobs/generate_embeddings_job_test.rb`

**Step 1-5:** Follow spec/05 Task 2 Steps 1-5.

**Step 6: Commit**

```bash
git add -A && git commit -m "feat: add GenerateEmbeddingsJob with OpenAI text-embedding-3-small"
```

---

### Task 8: ExtractKnowledgeGraphJob

**Files:**
- Create: `app/jobs/extract_knowledge_graph_job.rb`
- Create: `test/jobs/extract_knowledge_graph_job_test.rb`

**Step 1: Write failing tests**

```ruby
# test/jobs/extract_knowledge_graph_job_test.rb
require "test_helper"

class ExtractKnowledgeGraphJobTest < ActiveJob::TestCase
  setup do
    @meeting = meetings(:two)
    @meeting.update!(status: :processing)
    @transcript = transcripts(:two)
    @transcript.update!(status: :completed)

    @transcript.transcript_segments.create!(
      speaker: "Alice", content: "We need to finalize the API redesign by next week.",
      start_time: 0.0, end_time: 4.0, position: 0
    )
    @transcript.transcript_segments.create!(
      speaker: "Bob", content: "I'll handle the Ruby migration for the backend.",
      start_time: 4.0, end_time: 8.0, position: 1
    )
  end

  test "extracts entities and relationships from transcript" do
    fake_response = {
      "entities" => [
        { "name" => "Alice", "entity_type" => "person", "properties" => {} },
        { "name" => "Bob", "entity_type" => "person", "properties" => {} },
        { "name" => "API Redesign", "entity_type" => "project", "properties" => {} },
        { "name" => "Ruby Migration", "entity_type" => "topic", "properties" => {} }
      ],
      "relationships" => [
        { "source" => "Alice", "target" => "API Redesign", "relationship_type" => "works_on" },
        { "source" => "Bob", "target" => "Ruby Migration", "relationship_type" => "assigned_to" }
      ]
    }.to_json

    mock_chat = Minitest::Mock.new
    mock_chat.expect(:ask, OpenStruct.new(content: fake_response), [String])

    fake_embedding = Array.new(1536, 0.1)

    RubyLLM.stub(:chat, ->(**_kwargs) { mock_chat }) do
      RubyLLM.stub(:embed, ->(*args, **kwargs) {
        texts = args.first
        texts = [texts] unless texts.is_a?(Array)
        OpenStruct.new(vectors: texts.map { OpenStruct.new(embedding: fake_embedding) })
      }) do
        ExtractKnowledgeGraphJob.perform_now(@meeting.id)
      end
    end

    user = @meeting.user
    assert user.knowledge_entities.where(name: "Alice", entity_type: "person").exists?
    assert user.knowledge_entities.where(name: "Bob", entity_type: "person").exists?
    assert user.knowledge_entities.where(name: "API Redesign", entity_type: "project").exists?

    alice = user.knowledge_entities.find_by(name: "Alice")
    api_redesign = user.knowledge_entities.find_by(name: "API Redesign")
    assert KnowledgeRelationship.where(
      source_entity: alice, target_entity: api_redesign,
      meeting: @meeting, relationship_type: "works_on"
    ).exists?

    mock_chat.verify
  end

  test "deduplicates entities by name and type" do
    existing = KnowledgeEntity.create!(
      user: @meeting.user, name: "Alice", entity_type: "person", mention_count: 2
    )

    fake_response = {
      "entities" => [
        { "name" => "Alice", "entity_type" => "person", "properties" => {} }
      ],
      "relationships" => []
    }.to_json

    mock_chat = Minitest::Mock.new
    mock_chat.expect(:ask, OpenStruct.new(content: fake_response), [String])

    fake_embedding = Array.new(1536, 0.1)

    RubyLLM.stub(:chat, ->(**_kwargs) { mock_chat }) do
      RubyLLM.stub(:embed, ->(*args, **kwargs) {
        texts = args.first
        texts = [texts] unless texts.is_a?(Array)
        OpenStruct.new(vectors: texts.map { OpenStruct.new(embedding: fake_embedding) })
      }) do
        ExtractKnowledgeGraphJob.perform_now(@meeting.id)
      end
    end

    assert_equal 1, @meeting.user.knowledge_entities.where(name: "Alice", entity_type: "person").count
    assert_equal 3, existing.reload.mention_count

    mock_chat.verify
  end

  test "creates entity mentions with context" do
    fake_response = {
      "entities" => [
        { "name" => "Alice", "entity_type" => "person", "properties" => {} }
      ],
      "relationships" => []
    }.to_json

    mock_chat = Minitest::Mock.new
    mock_chat.expect(:ask, OpenStruct.new(content: fake_response), [String])

    fake_embedding = Array.new(1536, 0.1)

    RubyLLM.stub(:chat, ->(**_kwargs) { mock_chat }) do
      RubyLLM.stub(:embed, ->(*args, **kwargs) {
        texts = args.first
        texts = [texts] unless texts.is_a?(Array)
        OpenStruct.new(vectors: texts.map { OpenStruct.new(embedding: fake_embedding) })
      }) do
        ExtractKnowledgeGraphJob.perform_now(@meeting.id)
      end
    end

    alice = @meeting.user.knowledge_entities.find_by(name: "Alice")
    mention = KnowledgeEntityMention.find_by(knowledge_entity: alice, meeting: @meeting)
    assert_not_nil mention

    mock_chat.verify
  end

  test "handles AI error gracefully — does not fail the meeting" do
    RubyLLM.stub(:chat, ->(**_kwargs) { raise StandardError, "API timeout" }) do
      ExtractKnowledgeGraphJob.perform_now(@meeting.id)
    end

    assert_equal "processing", @meeting.reload.status
  end

  test "handles malformed JSON gracefully" do
    mock_chat = Minitest::Mock.new
    mock_chat.expect(:ask, OpenStruct.new(content: "not valid json at all"), [String])

    RubyLLM.stub(:chat, ->(**_kwargs) { mock_chat }) do
      ExtractKnowledgeGraphJob.perform_now(@meeting.id)
    end

    assert_equal 0, @meeting.user.knowledge_entities.count
    mock_chat.verify
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bin/rails test test/jobs/extract_knowledge_graph_job_test.rb`
Expected: FAIL

**Step 3: Implement the job**

```ruby
# app/jobs/extract_knowledge_graph_job.rb
class ExtractKnowledgeGraphJob < ApplicationJob
  queue_as :default

  SYSTEM_PROMPT = <<~PROMPT
    You are a knowledge graph extractor. Given a meeting transcript, extract all notable
    entities and relationships between them.

    Entity types: person, topic, decision, project, technology, action_item, organization

    Relationship types: discussed, decided, assigned_to, works_on, mentioned_with, depends_on, followed_up

    Return a JSON object with this structure:
    {
      "entities": [
        { "name": "Entity Name", "entity_type": "person|topic|decision|...", "properties": {} }
      ],
      "relationships": [
        { "source": "Entity Name", "target": "Other Entity", "relationship_type": "works_on|discussed|..." }
      ]
    }

    Rules:
    - Use consistent entity names (e.g., always "Alice" not sometimes "Alice" and sometimes "Alice Smith")
    - Only extract entities that are meaningfully discussed, not just briefly mentioned
    - properties is optional — use it for extra context like role, email, rationale, etc.
    - Return ONLY the JSON, no other text
  PROMPT

  def perform(meeting_id)
    meeting = Meeting.find(meeting_id)
    transcript = meeting.transcript
    formatted_text = transcript.formatted_text

    model = Rails.application.config.ai.default_model
    chat = RubyLLM.chat(model: model)
    response = chat.ask("#{SYSTEM_PROMPT}\n\n---\n\nTranscript:\n\n#{formatted_text}")

    graph_data = parse_json(response.content)
    return if graph_data.nil?

    entities_map = process_entities(meeting.user, meeting, graph_data["entities"] || [])
    process_relationships(meeting, entities_map, graph_data["relationships"] || [])
    generate_entity_embeddings(entities_map.values)

    Rails.logger.info("Extracted #{entities_map.size} entities for meeting #{meeting_id}")
  rescue StandardError => e
    Rails.logger.error("ExtractKnowledgeGraphJob failed for meeting #{meeting_id}: #{e.message}")
    Rails.logger.error(e.backtrace&.first(5)&.join("\n"))
  end

  private

  def parse_json(content)
    json_str = content.gsub(/\A```(?:json)?\n?/, "").gsub(/\n?```\z/, "").strip
    JSON.parse(json_str)
  rescue JSON::ParserError => e
    Rails.logger.error("Failed to parse knowledge graph JSON: #{e.message}")
    nil
  end

  def process_entities(user, meeting, entities_data)
    entities_map = {}

    entities_data.each do |entity_data|
      name = entity_data["name"]&.strip
      entity_type = entity_data["entity_type"]&.strip
      next if name.blank? || entity_type.blank?
      next unless KnowledgeEntity::ENTITY_TYPES.include?(entity_type)

      entity = user.knowledge_entities.find_or_initialize_by(
        name: name,
        entity_type: entity_type
      )

      entity.properties = (entity.properties || {}).merge(entity_data["properties"] || {})
      entity.mention_count = (entity.mention_count || 0) + 1
      entity.save!

      KnowledgeEntityMention.find_or_create_by!(
        knowledge_entity: entity,
        meeting: meeting
      )

      entities_map[name] = entity
    end

    entities_map
  end

  def process_relationships(meeting, entities_map, relationships_data)
    relationships_data.each do |rel_data|
      source = entities_map[rel_data["source"]]
      target = entities_map[rel_data["target"]]
      rel_type = rel_data["relationship_type"]

      next if source.nil? || target.nil?
      next unless KnowledgeRelationship::RELATIONSHIP_TYPES.include?(rel_type)

      KnowledgeRelationship.find_or_create_by!(
        source_entity: source,
        target_entity: target,
        meeting: meeting,
        relationship_type: rel_type
      )
    end
  end

  def generate_entity_embeddings(entities)
    return if entities.empty?

    texts = entities.map { |e| "#{e.entity_type}: #{e.name}" }
    embedding_model = Rails.application.config.ai.embedding_model

    result = RubyLLM.embed(texts, model: embedding_model)
    vectors = result.respond_to?(:vectors) ? result.vectors : [result]

    entities.each_with_index do |entity, i|
      embedding = vectors[i]&.respond_to?(:embedding) ? vectors[i].embedding : nil
      entity.update!(embedding: embedding) if embedding
    end
  rescue StandardError => e
    Rails.logger.error("Failed to generate entity embeddings: #{e.message}")
  end
end
```

**Step 4: Run tests**

Run: `bin/rails test test/jobs/extract_knowledge_graph_job_test.rb`
Expected: All PASS

**Step 5: Commit**

```bash
git add -A && git commit -m "feat: add ExtractKnowledgeGraphJob for knowledge graph extraction from transcripts"
```

---

### Task 9: Meeting::Analyzable concern — trigger AI jobs after transcription

**Files:**
- Create: `app/models/meeting/analyzable.rb`
- Modify: `app/models/meeting.rb` (include the concern)
- Create: `test/models/meeting/analyzable_test.rb`

**Step 1: Write failing tests**

```ruby
# test/models/meeting/analyzable_test.rb
require "test_helper"

class Meeting::AnalyzableTest < ActiveSupport::TestCase
  test "enqueues AI processing jobs when meeting becomes transcribed" do
    meeting = meetings(:two)
    meeting.update!(status: :transcribed)
    meeting.create_transcript!(status: :completed) unless meeting.transcript

    assert_enqueued_jobs 4 do
      meeting.start_analysis!
    end
  end

  test "transitions meeting to processing status" do
    meeting = meetings(:two)
    meeting.update!(status: :transcribed)
    meeting.create_transcript!(status: :completed) unless meeting.transcript

    meeting.start_analysis!

    assert_equal "processing", meeting.reload.status
  end

  test "does not enqueue if already processing or completed" do
    meeting = meetings(:one)
    meeting.update!(status: :completed)

    assert_no_enqueued_jobs do
      meeting.start_analysis!
    end
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bin/rails test test/models/meeting/analyzable_test.rb`
Expected: FAIL

**Step 3: Implement the concern**

```ruby
# app/models/meeting/analyzable.rb
module Meeting::Analyzable
  extend ActiveSupport::Concern

  def start_analysis!
    return unless transcribed?

    update!(status: :processing)

    GenerateSummaryJob.perform_later(id)
    ExtractActionItemsJob.perform_later(id)
    GenerateEmbeddingsJob.perform_later(id)
    ExtractKnowledgeGraphJob.perform_later(id)
  end
end
```

**Step 4: Include in Meeting model**

Add `include Analyzable` to `app/models/meeting.rb`.

**Step 5: Wire up the trigger**

Find where the meeting transitions to `transcribed` status (end of `HappyScribe::Transcription::ExportFetch` or the `ExportFetchJob`) and add `meeting.start_analysis!`.

**Step 6: Run tests**

Run: `bin/rails test test/models/meeting/analyzable_test.rb`
Expected: All PASS

**Step 7: Commit**

```bash
git add -A && git commit -m "feat: add Meeting::Analyzable concern to trigger AI processing after transcription"
```

---

## Increment 2: RubyLLM Tools

### Task 10: TranscriptSearchTool

**Files:**
- Create: `app/tools/transcript_search_tool.rb`
- Create: `test/tools/transcript_search_tool_test.rb`

**Step 1: Write failing tests**

```ruby
# test/tools/transcript_search_tool_test.rb
require "test_helper"

class TranscriptSearchToolTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @tool = TranscriptSearchTool.new(@user)
  end

  test "has correct description" do
    assert_includes TranscriptSearchTool.description, "search"
  end

  test "has required parameters" do
    params = TranscriptSearchTool.parameters
    assert params.key?(:query)
  end

  test "returns formatted results from nearest neighbor search" do
    transcript = transcripts(:one)
    chunk = transcript.transcript_chunks.create!(
      content: "Speaker 1: We discussed the budget for Q3.",
      position: 0, start_time: 0.0, end_time: 5.0,
      embedding: Array.new(1536, 0.1)
    )

    fake_embedding = Array.new(1536, 0.1)

    RubyLLM.stub(:embed, ->(*args, **kwargs) {
      OpenStruct.new(vectors: [OpenStruct.new(embedding: fake_embedding)])
    }) do
      result = @tool.execute(query: "budget discussion")
      assert result.is_a?(String)
      assert_includes result, "budget"
    end
  end

  test "scopes results to current user" do
    other_user = users(:two)
    other_meeting = other_user.meetings.create!(title: "Other meeting", language: "en-US", status: :completed)
    other_transcript = other_meeting.create_transcript!(status: :completed)
    other_transcript.transcript_chunks.create!(
      content: "Secret data from another user",
      position: 0, embedding: Array.new(1536, 0.2)
    )

    fake_embedding = Array.new(1536, 0.1)

    RubyLLM.stub(:embed, ->(*args, **kwargs) {
      OpenStruct.new(vectors: [OpenStruct.new(embedding: fake_embedding)])
    }) do
      result = @tool.execute(query: "secret data")
      refute_includes result, "Secret data from another user"
    end
  end
end
```

**Step 2: Implement the tool**

```ruby
# app/tools/transcript_search_tool.rb
class TranscriptSearchTool < RubyLLM::Tool
  description "Searches across meeting transcripts using semantic similarity. " \
              "Use this to find specific discussions, quotes, or topics mentioned in meetings."

  param :query, desc: "What to search for in meeting transcripts"
  param :meeting_id, type: :integer, desc: "Optional: limit search to a specific meeting ID", required: false
  param :limit, type: :integer, desc: "Maximum number of results to return (default 5)", required: false

  def initialize(user)
    @user = user
  end

  def execute(query:, meeting_id: nil, limit: 5)
    embedding_model = Rails.application.config.ai.embedding_model
    result = RubyLLM.embed(query, model: embedding_model)
    vector = result.respond_to?(:vectors) ? result.vectors.first.embedding : result.embedding

    scope = TranscriptChunk
      .joins(transcript: :meeting)
      .where(meetings: { user_id: @user.id })

    scope = scope.where(transcripts: { meeting_id: meeting_id }) if meeting_id

    chunks = scope.nearest_neighbors(:embedding, vector, distance: "cosine").first(limit)

    return "No relevant transcript content found." if chunks.empty?

    chunks.map { |c| format_chunk(c) }.join("\n\n---\n\n")
  end

  private

  def format_chunk(chunk)
    meeting = chunk.transcript.meeting
    time_range = [chunk.start_time, chunk.end_time].compact.map { |t| format_time(t) }.join(" - ")

    "Meeting: \"#{meeting.title}\" (#{meeting.created_at.strftime('%Y-%m-%d')})\n" \
    "Time: #{time_range}\n\n" \
    "#{chunk.content}"
  end

  def format_time(seconds)
    Time.at(seconds).utc.strftime("%H:%M:%S")
  end
end
```

**Step 3: Run tests**

Run: `bin/rails test test/tools/transcript_search_tool_test.rb`
Expected: All PASS

**Step 4: Commit**

```bash
git add -A && git commit -m "feat: add TranscriptSearchTool for semantic transcript search via pgvector"
```

---

### Task 11: KnowledgeGraphQueryTool

**Files:**
- Create: `app/tools/knowledge_graph_query_tool.rb`
- Create: `test/tools/knowledge_graph_query_tool_test.rb`

**Step 1: Write failing tests**

```ruby
# test/tools/knowledge_graph_query_tool_test.rb
require "test_helper"

class KnowledgeGraphQueryToolTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @tool = KnowledgeGraphQueryTool.new(@user)

    knowledge_entities(:api_redesign).update!(embedding: Array.new(1536, 0.1))
    knowledge_entities(:alice).update!(embedding: Array.new(1536, 0.2))
  end

  test "has correct description" do
    assert_includes KnowledgeGraphQueryTool.description, "knowledge graph"
  end

  test "finds entities by semantic search" do
    fake_embedding = Array.new(1536, 0.1)

    RubyLLM.stub(:embed, ->(*args, **kwargs) {
      OpenStruct.new(vectors: [OpenStruct.new(embedding: fake_embedding)])
    }) do
      result = @tool.execute(query: "API project")
      assert result.is_a?(String)
      assert_includes result, "API Redesign"
    end
  end

  test "filters by entity_type" do
    fake_embedding = Array.new(1536, 0.15)

    RubyLLM.stub(:embed, ->(*args, **kwargs) {
      OpenStruct.new(vectors: [OpenStruct.new(embedding: fake_embedding)])
    }) do
      result = @tool.execute(query: "Alice", entity_type: "person")
      assert_includes result, "Alice"
    end
  end

  test "includes relationships in output" do
    fake_embedding = Array.new(1536, 0.2)

    RubyLLM.stub(:embed, ->(*args, **kwargs) {
      OpenStruct.new(vectors: [OpenStruct.new(embedding: fake_embedding)])
    }) do
      result = @tool.execute(query: "Alice")
      assert_includes result, "works_on"
    end
  end

  test "scopes to current user only" do
    other_user = users(:two)
    KnowledgeEntity.create!(
      user: other_user, name: "Secret Project", entity_type: "project",
      embedding: Array.new(1536, 0.1)
    )

    fake_embedding = Array.new(1536, 0.1)

    RubyLLM.stub(:embed, ->(*args, **kwargs) {
      OpenStruct.new(vectors: [OpenStruct.new(embedding: fake_embedding)])
    }) do
      result = @tool.execute(query: "Secret Project")
      refute_includes result, "Secret Project"
    end
  end
end
```

**Step 2: Implement the tool**

```ruby
# app/tools/knowledge_graph_query_tool.rb
class KnowledgeGraphQueryTool < RubyLLM::Tool
  description "Queries the knowledge graph to find entities (people, topics, decisions, " \
              "projects, technologies) and their relationships across all meetings. " \
              "Use this to answer questions about who worked on what, what was decided, etc."

  param :query, desc: "What to look up (e.g., 'What has Alice worked on?', 'API redesign decisions')"
  param :entity_type, type: :string, desc: "Filter by type: person, topic, decision, project, technology, action_item, organization", required: false
  param :limit, type: :integer, desc: "Maximum entities to return (default 5)", required: false

  def initialize(user)
    @user = user
  end

  def execute(query:, entity_type: nil, limit: 5)
    embedding_model = Rails.application.config.ai.embedding_model
    result = RubyLLM.embed(query, model: embedding_model)
    vector = result.respond_to?(:vectors) ? result.vectors.first.embedding : result.embedding

    scope = @user.knowledge_entities
    scope = scope.where(entity_type: entity_type) if entity_type

    entities = scope.nearest_neighbors(:embedding, vector, distance: "cosine").first(limit)

    return "No relevant entities found in the knowledge graph." if entities.empty?

    entities.map { |e| format_entity_with_relationships(e) }.join("\n\n===\n\n")
  end

  private

  def format_entity_with_relationships(entity)
    lines = []
    lines << "#{entity.entity_type.titleize}: #{entity.name} (mentioned #{entity.mention_count} times)"

    if entity.properties.present? && entity.properties.any?
      lines << "Properties: #{entity.properties.map { |k, v| "#{k}: #{v}" }.join(', ')}"
    end

    outgoing = entity.outgoing_relationships.includes(:target_entity).limit(10)
    if outgoing.any?
      lines << "Relationships:"
      outgoing.each do |rel|
        lines << "  -> #{rel.relationship_type} -> #{rel.target_entity.name} (#{rel.target_entity.entity_type})"
      end
    end

    incoming = entity.incoming_relationships.includes(:source_entity).limit(10)
    if incoming.any?
      incoming.each do |rel|
        lines << "  <- #{rel.relationship_type} <- #{rel.source_entity.name} (#{rel.source_entity.entity_type})"
      end
    end

    meetings = entity.meetings.distinct.order(created_at: :desc).limit(5)
    if meetings.any?
      lines << "Mentioned in: #{meetings.map { |m| "\"#{m.title}\" (#{m.created_at.strftime('%Y-%m-%d')})" }.join(', ')}"
    end

    lines.join("\n")
  end
end
```

**Step 3: Run tests**

Run: `bin/rails test test/tools/knowledge_graph_query_tool_test.rb`
Expected: All PASS

**Step 4: Commit**

```bash
git add -A && git commit -m "feat: add KnowledgeGraphQueryTool for entity and relationship queries"
```

---

### Task 12: MeetingLookupTool

**Files:**
- Create: `app/tools/meeting_lookup_tool.rb`
- Create: `test/tools/meeting_lookup_tool_test.rb`

**Step 1: Write failing tests**

```ruby
# test/tools/meeting_lookup_tool_test.rb
require "test_helper"

class MeetingLookupToolTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @tool = MeetingLookupTool.new(@user)
  end

  test "finds meetings by title search" do
    result = @tool.execute(query: "Standup")
    assert_includes result, "Weekly Standup"
  end

  test "filters by date range" do
    result = @tool.execute(after: "2020-01-01", before: "2030-12-31")
    assert result.present?
  end

  test "filters by participant/speaker" do
    result = @tool.execute(participant: "Speaker 1")
    assert_includes result, "Weekly Standup"
  end

  test "scopes to current user" do
    other_user = users(:two)
    other_user.meetings.create!(title: "Secret Meeting", language: "en-US", status: :completed)

    result = @tool.execute(query: "Secret")
    refute_includes result, "Secret Meeting"
  end

  test "returns message when no meetings found" do
    result = @tool.execute(query: "NonexistentMeetingTitle12345")
    assert_includes result, "No meetings found"
  end
end
```

**Step 2: Implement the tool**

```ruby
# app/tools/meeting_lookup_tool.rb
class MeetingLookupTool < RubyLLM::Tool
  description "Finds meetings by title, date range, or participant/speaker. " \
              "Use this to identify which meetings to investigate further."

  param :query, type: :string, desc: "Search term for meeting titles", required: false
  param :after, type: :string, desc: "ISO date — only meetings after this date (e.g., '2026-01-15')", required: false
  param :before, type: :string, desc: "ISO date — only meetings before this date", required: false
  param :participant, type: :string, desc: "Speaker name to filter by", required: false
  param :limit, type: :integer, desc: "Maximum results (default 10)", required: false

  def initialize(user)
    @user = user
  end

  def execute(query: nil, after: nil, before: nil, participant: nil, limit: 10)
    scope = @user.meetings.where.not(status: [:uploading, :failed])

    scope = scope.where("title ILIKE ?", "%#{query}%") if query.present?
    scope = scope.where("meetings.created_at >= ?", Date.parse(after)) if after.present?
    scope = scope.where("meetings.created_at <= ?", Date.parse(before).end_of_day) if before.present?

    if participant.present?
      scope = scope.joins(transcript: :transcript_segments)
                   .where("transcript_segments.speaker ILIKE ?", "%#{participant}%")
                   .distinct
    end

    meetings = scope.order(created_at: :desc).limit(limit)

    return "No meetings found matching your criteria." if meetings.empty?

    meetings.map { |m| format_meeting(m) }.join("\n\n")
  end

  private

  def format_meeting(meeting)
    speakers = meeting.transcript&.transcript_segments&.select(:speaker)&.distinct&.pluck(:speaker)&.compact || []

    "ID: #{meeting.id} | \"#{meeting.title}\"\n" \
    "Date: #{meeting.created_at.strftime('%Y-%m-%d %H:%M')}\n" \
    "Status: #{meeting.status}\n" \
    "Speakers: #{speakers.any? ? speakers.join(', ') : 'Unknown'}"
  end
end
```

**Step 3: Run tests**

Run: `bin/rails test test/tools/meeting_lookup_tool_test.rb`
Expected: All PASS

**Step 4: Commit**

```bash
git add -A && git commit -m "feat: add MeetingLookupTool for finding meetings by title, date, and participants"
```

---

### Task 13: ActionItemsTool

**Files:**
- Create: `app/tools/action_items_tool.rb`
- Create: `test/tools/action_items_tool_test.rb`

**Step 1: Write failing tests**

```ruby
# test/tools/action_items_tool_test.rb
require "test_helper"

class ActionItemsToolTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @tool = ActionItemsTool.new(@user)
  end

  test "lists all action items for user" do
    result = @tool.execute
    assert_includes result, "Send the Q3 report"
    assert_includes result, "Schedule follow-up meeting"
  end

  test "filters by assignee" do
    result = @tool.execute(assignee: "Sarah")
    assert_includes result, "Send the Q3 report"
    refute_includes result, "Schedule follow-up meeting"
  end

  test "filters by completion status" do
    action_items(:one).update!(completed: true)
    result = @tool.execute(completed: false)
    refute_includes result, "Send the Q3 report"
    assert_includes result, "Schedule follow-up meeting"
  end

  test "filters by meeting_id" do
    other_meeting = @user.meetings.create!(title: "Other", language: "en-US", status: :completed)
    other_meeting.action_items.create!(description: "Other meeting task")

    result = @tool.execute(meeting_id: meetings(:one).id)
    assert_includes result, "Send the Q3 report"
    refute_includes result, "Other meeting task"
  end

  test "scopes to current user" do
    other_user = users(:two)
    other_meeting = other_user.meetings.create!(title: "Other", language: "en-US", status: :completed)
    other_meeting.action_items.create!(description: "Secret task")

    result = @tool.execute
    refute_includes result, "Secret task"
  end
end
```

**Step 2: Implement the tool**

```ruby
# app/tools/action_items_tool.rb
class ActionItemsTool < RubyLLM::Tool
  description "Lists action items extracted from meetings. " \
              "Can filter by assignee, completion status, or specific meeting."

  param :assignee, type: :string, desc: "Filter by person assigned to the task", required: false
  param :completed, type: :boolean, desc: "Filter: true for done, false for pending", required: false
  param :meeting_id, type: :integer, desc: "Filter by specific meeting ID", required: false
  param :limit, type: :integer, desc: "Maximum results (default 20)", required: false

  def initialize(user)
    @user = user
  end

  def execute(assignee: nil, completed: nil, meeting_id: nil, limit: 20)
    scope = ActionItem.joins(:meeting).where(meetings: { user_id: @user.id })

    scope = scope.where("action_items.assignee ILIKE ?", "%#{assignee}%") if assignee.present?
    scope = scope.where(completed: completed) unless completed.nil?
    scope = scope.where(meeting_id: meeting_id) if meeting_id

    items = scope.includes(:meeting).order(created_at: :desc).limit(limit)

    return "No action items found." if items.empty?

    items.map { |ai| format_action_item(ai) }.join("\n\n")
  end

  private

  def format_action_item(item)
    status = item.completed? ? "[DONE]" : "[PENDING]"
    assignee = item.assignee.present? ? " (assigned to: #{item.assignee})" : ""
    due = item.due_date.present? ? " | Due: #{item.due_date}" : ""

    "#{status} #{item.description}#{assignee}#{due}\n" \
    "  From: \"#{item.meeting.title}\" (#{item.meeting.created_at.strftime('%Y-%m-%d')})"
  end
end
```

**Step 3: Run tests**

Run: `bin/rails test test/tools/action_items_tool_test.rb`
Expected: All PASS

**Step 4: Commit**

```bash
git add -A && git commit -m "feat: add ActionItemsTool for querying action items across meetings"
```

---

### Task 14: MeetingSummaryTool

**Files:**
- Create: `app/tools/meeting_summary_tool.rb`
- Create: `test/tools/meeting_summary_tool_test.rb`

**Step 1: Write failing tests**

```ruby
# test/tools/meeting_summary_tool_test.rb
require "test_helper"

class MeetingSummaryToolTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @tool = MeetingSummaryTool.new(@user)
  end

  test "returns existing summary" do
    meeting = meetings(:one)
    meeting.create_summary!(content: "This was a productive meeting about Q3.", model_used: "test") unless meeting.summary

    result = @tool.execute(meeting_id: meeting.id)
    assert_includes result, "productive meeting"
  end

  test "raises ActiveRecord::RecordNotFound for other user's meeting" do
    other_user = users(:two)
    other_meeting = other_user.meetings.create!(title: "Other", language: "en-US", status: :completed)

    assert_raises(ActiveRecord::RecordNotFound) do
      @tool.execute(meeting_id: other_meeting.id)
    end
  end

  test "returns message when no summary exists" do
    meeting = meetings(:two)
    result = @tool.execute(meeting_id: meeting.id)
    assert_includes result, "No summary"
  end
end
```

**Step 2: Implement the tool**

```ruby
# app/tools/meeting_summary_tool.rb
class MeetingSummaryTool < RubyLLM::Tool
  description "Retrieves the AI-generated summary for a specific meeting. " \
              "Use the meeting_lookup tool first to find the meeting ID."

  param :meeting_id, type: :integer, desc: "The meeting ID to get the summary for"

  def initialize(user)
    @user = user
  end

  def execute(meeting_id:)
    meeting = @user.meetings.find(meeting_id)
    summary = meeting.summary

    return "No summary available yet for \"#{meeting.title}\"." unless summary

    "Summary for \"#{meeting.title}\" (#{meeting.created_at.strftime('%Y-%m-%d')}):\n\n" \
    "#{summary.content.to_plain_text}"
  end
end
```

**Step 3: Run tests**

Run: `bin/rails test test/tools/meeting_summary_tool_test.rb`
Expected: All PASS

**Step 4: Commit**

```bash
git add -A && git commit -m "feat: add MeetingSummaryTool for retrieving meeting summaries"
```

---

### Task 15: DraftFollowUpTool

**Files:**
- Create: `app/tools/draft_follow_up_tool.rb`
- Create: `test/tools/draft_follow_up_tool_test.rb`

**Step 1: Write failing tests**

```ruby
# test/tools/draft_follow_up_tool_test.rb
require "test_helper"

class DraftFollowUpToolTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @tool = DraftFollowUpTool.new(@user)
  end

  test "drafts a follow-up email for a meeting" do
    meeting = meetings(:one)
    meeting.create_summary!(content: "Discussed Q3 roadmap.", model_used: "test") unless meeting.summary
    meeting.action_items.create!(description: "Send report", assignee: "Sarah") unless meeting.action_items.any?

    fake_response = "Subject: Follow-up from Weekly Standup\n\nHi team,\n\nHere are the key takeaways..."

    mock_chat = Minitest::Mock.new
    mock_chat.expect(:ask, OpenStruct.new(content: fake_response), [String])

    RubyLLM.stub(:chat, ->(**_kwargs) { mock_chat }) do
      result = @tool.execute(meeting_id: meeting.id)
      assert_includes result, "Follow-up"
    end

    mock_chat.verify
  end

  test "raises for other user's meeting" do
    other_user = users(:two)
    other_meeting = other_user.meetings.create!(title: "Other", language: "en-US", status: :completed)

    assert_raises(ActiveRecord::RecordNotFound) do
      @tool.execute(meeting_id: other_meeting.id)
    end
  end
end
```

**Step 2: Implement the tool**

```ruby
# app/tools/draft_follow_up_tool.rb
class DraftFollowUpTool < RubyLLM::Tool
  description "Drafts a follow-up email based on a meeting's summary and action items. " \
              "Returns the draft text for review before sending."

  param :meeting_id, type: :integer, desc: "The meeting ID to draft a follow-up for"
  param :tone, type: :string, desc: "Email tone: formal, casual, brief (default: professional)", required: false
  param :focus, type: :string, desc: "What to emphasize (e.g., 'action items', 'decisions')", required: false

  def initialize(user)
    @user = user
  end

  def execute(meeting_id:, tone: "professional", focus: nil)
    meeting = @user.meetings.find(meeting_id)
    context = build_meeting_context(meeting)

    prompt = build_prompt(tone, focus, context)

    model = Rails.application.config.ai.default_model
    response = RubyLLM.chat(model: model).ask(prompt)
    response.content
  end

  private

  def build_meeting_context(meeting)
    parts = []
    parts << "Meeting: \"#{meeting.title}\" on #{meeting.created_at.strftime('%Y-%m-%d')}"

    if meeting.summary
      parts << "Summary:\n#{meeting.summary.content.to_plain_text}"
    end

    if meeting.action_items.any?
      items = meeting.action_items.map do |ai|
        assignee = ai.assignee.present? ? " (#{ai.assignee})" : ""
        due = ai.due_date.present? ? " by #{ai.due_date}" : ""
        "- #{ai.description}#{assignee}#{due}"
      end
      parts << "Action Items:\n#{items.join("\n")}"
    end

    if meeting.transcript
      parts << "Speakers: #{meeting.transcript.transcript_segments.select(:speaker).distinct.pluck(:speaker).compact.join(', ')}"
    end

    parts.join("\n\n")
  end

  def build_prompt(tone, focus, context)
    prompt = "Draft a #{tone} follow-up email for this meeting.\n"
    prompt += "Focus on: #{focus}\n" if focus.present?
    prompt += "\n#{context}"
    prompt
  end
end
```

**Step 3: Run tests**

Run: `bin/rails test test/tools/draft_follow_up_tool_test.rb`
Expected: All PASS

**Step 4: Commit**

```bash
git add -A && git commit -m "feat: add DraftFollowUpTool for AI-drafted follow-up emails"
```

---

## Increment 3: Agentic Chat Interface (RubyLLM `acts_as_chat`)

### Task 16: Install RubyLLM Rails integration

**Files:**
- Generated by: `rails generate ruby_llm:install`
- Creates: migrations for `chats`, `messages`, `tool_calls`, `models` tables
- Creates: `app/models/chat.rb`, `app/models/message.rb`, `app/models/tool_call.rb`, `app/models/model.rb`

**Step 1: Run the RubyLLM install generator**

Run: `bin/rails generate ruby_llm:install`

Review generated files — ensure no conflicts with existing models.

**Step 2: Enable the new API in the initializer**

Ensure `config/initializers/ruby_llm.rb` contains:
```ruby
RubyLLM.configure do |config|
  config.openai_api_key = ENV["OPENAI_API_KEY"]
  config.anthropic_api_key = ENV["ANTHROPIC_API_KEY"]
  config.use_new_acts_as = true
end
```

**Step 3: Run migrations**

Run: `bin/rails db:migrate`

**Step 4: Load models into the database**

Run: `bin/rails ruby_llm:load_models`

**Step 5: Commit**

```bash
git add -A && git commit -m "feat: install RubyLLM Rails integration with acts_as_chat persistence"
```

---

### Task 17: Customize Chat model with tools and user scoping

**Files:**
- Modify: `app/models/chat.rb` (add user association, tool registration)
- Create: `db/migrate/TIMESTAMP_add_user_to_chats.rb`
- Modify: `app/models/user.rb` (add `has_many :chats`)
- Create: `test/models/chat_test.rb`

**Step 1: Add user_id to chats table**

```ruby
# db/migrate/TIMESTAMP_add_user_to_chats.rb
class AddUserToChats < ActiveRecord::Migration[8.1]
  def change
    add_reference :chats, :user, null: false, foreign_key: true
  end
end
```

**Step 2: Customize the Chat model**

```ruby
# app/models/chat.rb
class Chat < ApplicationRecord
  acts_as_chat

  belongs_to :user

  SYSTEM_PROMPT = <<~PROMPT
    You are a meeting assistant with access to the user's complete meeting history.
    You can search transcripts, query the knowledge graph, look up meetings,
    review action items, get summaries, and draft follow-up emails.

    When answering questions:
    - Use tools to find specific information rather than guessing
    - Cite which meeting(s) your information comes from
    - For cross-meeting questions, search broadly then narrow down
    - When asked about people or topics, check the knowledge graph first
    - Be concise and direct in your answers

    The user's meetings are transcribed from audio recordings.
    Today's date is %{date}.
  PROMPT

  def with_assistant
    with_instructions(SYSTEM_PROMPT % { date: Date.today.to_s }, replace: true)
      .with_model("claude-sonnet-4-20250514")
      .with_tools(
        TranscriptSearchTool.new(user),
        KnowledgeGraphQueryTool.new(user),
        MeetingLookupTool.new(user),
        ActionItemsTool.new(user),
        MeetingSummaryTool.new(user),
        DraftFollowUpTool.new(user)
      )
      .with_temperature(0.3)
  end
end
```

**Step 3: Update User model**

Add to `app/models/user.rb`:
```ruby
has_many :chats, dependent: :destroy
```

**Step 4: Run migration and tests**

Run: `bin/rails db:migrate && bin/rails test test/models/chat_test.rb`
Expected: All PASS

**Step 5: Commit**

```bash
git add -A && git commit -m "feat: customize Chat model with meeting assistant tools and user scoping"
```

---

### Task 18: ChatsController, ChatMessagesController, and routes

**Files:**
- Create: `app/controllers/chats_controller.rb`
- Create: `app/controllers/chat_messages_controller.rb`
- Modify: `config/routes.rb`
- Create: `test/controllers/chats_controller_test.rb`

**Step 1: Write failing tests**

```ruby
# test/controllers/chats_controller_test.rb
require "test_helper"

class ChatsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    log_in_as(@user)
  end

  test "GET /chats creates a new chat and redirects" do
    assert_difference("Chat.count", 1) do
      get chats_path
    end
    assert_redirected_to chat_path(Chat.last)
  end

  test "GET /chats/:id shows the chat" do
    chat = Chat.create!(user: @user)
    get chat_path(chat)
    assert_response :success
  end

  test "POST /chats/:id/messages creates user message and enqueues job" do
    chat = Chat.create!(user: @user)

    assert_enqueued_jobs 1, only: AssistantRespondJob do
      post chat_messages_path(chat), params: { message: "What meetings did I have last week?" }
    end

    assert_redirected_to chat_path(chat)
  end

  test "cannot access another user's chat" do
    other_user = users(:two)
    other_chat = Chat.create!(user: other_user)

    get chat_path(other_chat)
    assert_redirected_to chats_path
  end
end
```

**Step 2: Add routes**

```ruby
# config/routes.rb — add:
resources :chats, only: [:index, :show] do
  resources :messages, only: [:create], controller: "chat_messages"
end
```

**Step 3: Implement controllers**

```ruby
# app/controllers/chats_controller.rb
class ChatsController < ApplicationController
  before_action :set_chat, only: :show

  def index
    chat = Current.user.chats.create!
    redirect_to chat_path(chat)
  end

  def show
    @messages = @chat.messages.order(created_at: :asc)
  end

  private

  def set_chat
    @chat = Current.user.chats.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to chats_path
  end
end
```

```ruby
# app/controllers/chat_messages_controller.rb
class ChatMessagesController < ApplicationController
  before_action :set_chat

  def create
    @chat.with_assistant.create_user_message(params[:message])
    AssistantRespondJob.perform_later(@chat.id)
    redirect_to chat_path(@chat)
  end

  private

  def set_chat
    @chat = Current.user.chats.find(params[:chat_id])
  end
end
```

**Step 4: Run tests**

Run: `bin/rails test test/controllers/chats_controller_test.rb`
Expected: All PASS

**Step 5: Commit**

```bash
git add -A && git commit -m "feat: add ChatsController and ChatMessagesController with routes"
```

---

### Task 19: AssistantRespondJob — background processing with Turbo Streams

**Files:**
- Create: `app/jobs/assistant_respond_job.rb`
- Create: `test/jobs/assistant_respond_job_test.rb`

**Step 1: Write failing tests**

```ruby
# test/jobs/assistant_respond_job_test.rb
require "test_helper"

class AssistantRespondJobTest < ActiveJob::TestCase
  test "can be enqueued" do
    chat = Chat.create!(user: users(:one))
    chat.with_assistant.create_user_message("Hello")

    assert_enqueued_with(job: AssistantRespondJob, args: [chat.id]) do
      AssistantRespondJob.perform_later(chat.id)
    end
  end
end
```

**Step 2: Implement the job**

```ruby
# app/jobs/assistant_respond_job.rb
class AssistantRespondJob < ApplicationJob
  queue_as :default

  def perform(chat_id)
    chat = Chat.find(chat_id)

    chat.with_assistant.complete do |chunk|
      if chunk.content.present?
        Turbo::StreamsChannel.broadcast_append_to(
          "chat_#{chat.id}",
          target: "chat_messages",
          html: chunk.content
        )
      end
    end
  rescue StandardError => e
    Rails.logger.error("AssistantRespondJob failed for chat #{chat_id}: #{e.message}")

    Turbo::StreamsChannel.broadcast_append_to(
      "chat_#{chat.id}",
      target: "chat_messages",
      html: "<div class='text-red-500'>Sorry, something went wrong. Please try again.</div>"
    )
  end
end
```

**Step 3: Run tests**

Run: `bin/rails test test/jobs/assistant_respond_job_test.rb`
Expected: All PASS

**Step 4: Commit**

```bash
git add -A && git commit -m "feat: add AssistantRespondJob with Turbo Stream broadcasting"
```

---

### Task 20: Chat views

**Files:**
- Create: `app/views/chats/show.html.erb`
- Create: `app/views/chat_messages/_message.html.erb`

**Step 1: Create the chat show view**

```erb
<%# app/views/chats/show.html.erb %>
<%= turbo_stream_from "chat_#{@chat.id}" %>

<div class="max-w-3xl mx-auto py-8">
  <div class="flex items-center justify-between mb-6">
    <h1 class="text-2xl font-bold">Meeting Assistant</h1>
    <%= link_to "New Chat", chats_path, class: "text-blue-600 hover:underline" %>
  </div>

  <div id="chat_messages" class="space-y-4 mb-6 min-h-[200px]">
    <% @messages.each do |message| %>
      <%= render "chat_messages/message", message: message %>
    <% end %>
  </div>

  <%= form_with url: chat_messages_path(@chat), method: :post, class: "flex gap-2" do |f| %>
    <%= f.text_field :message,
        placeholder: "Ask about your meetings...",
        class: "flex-1 rounded-lg border border-gray-300 px-4 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500",
        autofocus: true,
        autocomplete: "off" %>
    <%= f.submit "Send",
        class: "bg-blue-600 text-white px-6 py-2 rounded-lg hover:bg-blue-700 cursor-pointer" %>
  <% end %>
</div>
```

**Step 2: Create the message partial**

```erb
<%# app/views/chat_messages/_message.html.erb %>
<% if message.role == "user" %>
  <div class="flex justify-end">
    <div class="bg-blue-600 text-white rounded-lg px-4 py-2 max-w-[80%]">
      <%= simple_format(message.content) %>
    </div>
  </div>
<% elsif message.role == "assistant" && message.content.present? %>
  <div class="flex justify-start">
    <div class="bg-gray-100 rounded-lg px-4 py-2 max-w-[80%]">
      <%= simple_format(message.content) %>
    </div>
  </div>
<% end %>
```

**Step 3: Commit**

```bash
git add -A && git commit -m "feat: add chat views with Turbo Stream subscription for real-time responses"
```

---

### Task 21: Navigation link and final integration test

**Files:**
- Modify: `app/views/layouts/application.html.erb` (add "Chat" nav link)
- Create: `test/integration/chat_flow_test.rb`

**Step 1: Add navigation link**

Add to the app layout, visible when logged in:
```erb
<%= link_to "Meeting Assistant", chats_path %>
```

**Step 2: Write integration test**

```ruby
# test/integration/chat_flow_test.rb
require "test_helper"

class ChatFlowTest < ActionDispatch::IntegrationTest
  test "user can create a chat and send a message" do
    log_in_as(users(:one))

    get chats_path
    assert_response :redirect
    follow_redirect!
    assert_response :success

    chat = Chat.last
    assert_equal users(:one), chat.user

    assert_enqueued_jobs 1, only: AssistantRespondJob do
      post chat_messages_path(chat), params: { message: "What meetings did I have?" }
    end

    assert_redirected_to chat_path(chat)
    follow_redirect!
    assert_response :success
  end
end
```

**Step 3: Run all tests**

Run: `bin/rails test`
Expected: All PASS

**Step 4: Commit**

```bash
git add -A && git commit -m "feat: add chat navigation and integration test"
```

---

## Summary of All Tasks

| # | Task | Increment | Key Files |
|---|------|-----------|-----------|
| 1 | Summary, ActionItem, TranscriptChunk models | 1 | models, migrations, tests |
| 2 | Knowledge graph models | 1 | KnowledgeEntity, KnowledgeRelationship, KnowledgeEntityMention |
| 3 | AI config initializer | 1 | `config/initializers/ai.rb` |
| 4 | TranscriptChunker service | 1 | `app/services/transcript_chunker.rb` |
| 5 | GenerateSummaryJob | 1 | `app/jobs/generate_summary_job.rb` |
| 6 | ExtractActionItemsJob | 1 | `app/jobs/extract_action_items_job.rb` |
| 7 | GenerateEmbeddingsJob | 1 | `app/jobs/generate_embeddings_job.rb` |
| 8 | ExtractKnowledgeGraphJob | 1 | `app/jobs/extract_knowledge_graph_job.rb` |
| 9 | Meeting::Analyzable concern | 1 | `app/models/meeting/analyzable.rb` |
| 10 | TranscriptSearchTool | 2 | `app/tools/transcript_search_tool.rb` |
| 11 | KnowledgeGraphQueryTool | 2 | `app/tools/knowledge_graph_query_tool.rb` |
| 12 | MeetingLookupTool | 2 | `app/tools/meeting_lookup_tool.rb` |
| 13 | ActionItemsTool | 2 | `app/tools/action_items_tool.rb` |
| 14 | MeetingSummaryTool | 2 | `app/tools/meeting_summary_tool.rb` |
| 15 | DraftFollowUpTool | 2 | `app/tools/draft_follow_up_tool.rb` |
| 16 | Install RubyLLM Rails integration | 3 | generated models, migrations |
| 17 | Customize Chat model | 3 | `app/models/chat.rb` |
| 18 | ChatsController + routes | 3 | controllers, routes |
| 19 | AssistantRespondJob | 3 | `app/jobs/assistant_respond_job.rb` |
| 20 | Chat views | 3 | `app/views/chats/` |
| 21 | Navigation + integration test | 3 | layout, integration test |

**Total: 21 tasks across 3 increments.**
