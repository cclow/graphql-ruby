require 'spec_helper'

describe GraphQL::Query do
  let(:query_string) { "post(123) { title, content } "}
  let(:context) { Context.new(person_name: "Han Solo") }
  let(:query) { GraphQL::Query.new(query_string, context: context) }
  let(:result) { query.as_result }

  before do
    @post = Post.create(id: 123, content: "So many great things", title: "My great post", published_at: Date.new(2010,1,4))
    @comment1 = Comment.create(id: 444, post_id: 123, content: "I agree", rating: 5)
    @comment2 = Comment.create(id: 445, post_id: 123, content: "I disagree", rating: 1)
    @like1 = Like.create(id: 991, post_id: 123)
    @like2 = Like.create(id: 992, post_id: 123)
  end

  after do
    @post.destroy
    @comment1.destroy
    @comment2.destroy
    @like1.destroy
    @like2.destroy
  end

  describe '#as_result' do
    it 'finds fields that delegate to a target' do
      assert_equal result, {"123" => {"title" => "My great post", "content" => "So many great things"}}
    end

    describe 'with multiple roots' do
      let(:query_string) { "comment(444, 445) { content } "}
      it 'adds each as a key-value of the response' do
        assert_equal ["444", "445"], result.keys
      end
    end

    describe 'when accessing fields that return objects' do
      describe 'when making calls on the field' do
        let(:query_string) { "post(123) { published_at.minus_days(200) { year } }"}
        it 'returns the modified value' do
          assert_equal 2009, result["123"]["published_at"]["year"]
        end
      end
      describe 'when requesting more fields' do
        let(:query_string) { "post(123) { published_at { month, year } }"}
        it 'returns those fields' do
          assert_equal({"month" => 1, "year" => 2010}, result["123"]["published_at"])
        end
      end
    end

    describe 'when using query fragments' do
      let(:query_string) { "post(123) { id, $publishedData } $publishedData: { published_at { month, year } }"}

      it 'can yield the fragment' do
        fragment = query.fragments["$publishedData"]
        assert_equal "$publishedData", fragment.identifier
        assert_equal 1, fragment.fields.length
      end

      it 'returns literal fields and fragment fields' do
        assert_equal(123, result["123"]['id'])
        assert_equal({"month" => 1, "year" => 2010}, result["123"]["published_at"])
      end
    end
    describe 'when aliasing things' do
      let(:query_string) { "post(123) { title as headline, content as what_it_says }"}

      it 'applies aliases to fields' do
        assert_equal @post.title, result["123"]["headline"]
        assert_equal @post.content, result["123"]["what_it_says"]
      end

      it 'applies aliases to edges' # dunno the syntax yet
    end

    describe 'when requesting fields defined on the node' do
      let(:query_string) { "post(123) { length } "}
      it 'finds fields defined on the node' do
        assert_equal 20, result["123"]["length"]
      end
    end

    describe 'when accessing custom fields' do
      let(:query_string) { "comment(444) { letters }"}

      it 'uses the custom field' do
        assert_equal "I agree", result["444"]["letters"]
      end

      describe 'when making calls on fields' do
        let(:query_string) { "comment(444) {
            letters.select(4, 3),
            letters.from(3).for(2) as snippet
          }"}

        it 'works with aliases' do
          assert result["444"]["snippet"].present?
        end

        it 'applies calls' do
          assert_equal "gr", result["444"]["snippet"]
        end

        it 'applies calls with multiple arguments' do
          assert_equal "ree", result["444"]["letters"]
        end
      end

      describe 'when requesting fields overriden on a child class' do
        let(:query_string) { 'thumb_up(991) { id }'}
        it 'uses the child implementation' do
          assert_equal '991991', result["991991"]["id"]
        end
      end
    end

    describe 'when requesting an undefined field' do
      let(:query_string) { "post(123) { destroy } "}
      it 'raises a FieldNotDefined error' do
        assert_raises(GraphQL::FieldNotDefinedError) { query.as_result }
        assert(Post.find(123).present?)
      end
    end

    describe 'when the root call doesnt have an argument' do
      let(:query_string) { "context() { person_name, present }"}
      it 'calls the node with no arguments' do
        assert_equal true, result["context"]["present"]
        assert_equal "Han Solo", result["context"]["person_name"]
      end
    end

    describe  'when requesting a collection' do
      let(:query_string) { "post(123) {
          title,
          comments { count, edges { cursor, node { content } } }
        }"}

      it 'returns collection data' do
        assert_equal result, {
            "123" => {
              "title" => "My great post",
              "comments" => {
                "count" => 2,
                "edges" => [
                  { "cursor" => "444", "node" => {"content" => "I agree"} },
                  { "cursor" => "445", "node" => {"content" => "I disagree"}}
                ]
            }}}
      end
    end

    describe  'when making calls on a collection' do
      let(:query_string) { "post(123) { comments.first(1) { edges { cursor, node { content } } } }"}

      it 'executes those calls' do
        expected_result = { "123" => {
          "comments" => {
            "edges" => [
              { "cursor" => "444", "node" => { "content" => "I agree"} }
            ]
        }}}
        assert_equal(expected_result, result)
      end
    end

    describe  'when making DEEP calls on a collection' do
      let(:query_string) { "post(123) { comments.after(444).first(1) {
            edges { cursor, node { content } }
          }}"}

      it 'executes those calls' do
        assert_equal result, {
            "123" => {
              "comments" => {
                "edges" => [
                  {
                    "cursor" => "445",
                    "node" => { "content" => "I disagree"}
                  }
                ]
            }}}
      end
    end

    describe  'when requesting fields at collection-level' do
      let(:query_string) { "post(123) { comments { average_rating } }"}

      it 'executes those calls' do
        assert_equal result, { "123" => { "comments" => { "average_rating" => 3 } } }
      end
    end

    describe  'when making calls on node fields' do
      let(:query_string) { "post(123) { comments { edges { node { letters.from(3).for(3) }} } }"}

      it 'makes calls on the fields' do
        assert_equal ["gre", "isa"], result["123"]["comments"]["edges"].map {|e| e["node"]["letters"] }
      end
    end

    describe  'when requesting collection-level fields that dont exist' do
      let(:query_string) { "post(123) { comments { bogus_field } }"}

      it 'raises FieldNotDefined' do
        assert_raises(GraphQL::FieldNotDefinedError) { query.as_result }
      end
    end
  end

  describe 'when requesting fields on a related object' do
    let(:query_string) { "comment(444) { post { title } }"}

    it 'finds fields on that object' do
      assert_equal "My great post", result["444"]["post"]["title"]
    end

    describe 'when the object doesnt exist' do
      before do
        Post.all.map(&:destroy)
      end

      it 'blows_up' do # what _should_ this do?
        assert_raises(NoMethodError) { result }
      end
    end
  end

  describe 'when edge classes were named explicitly' do
    let(:query_string) { "post(123) { likes { any, edges { node { id } } } }"}

    it 'gets node values' do
      assert_equal ["991991","992992"], result["123"]["likes"]["edges"].map {|e|  e["node"]["id"] }
    end

    it 'gets edge values' do
      assert_equal true, result["123"]["likes"]["any"]
    end
  end

  describe '#context' do
    let(:query_string) { "context() { person_name }"}

    it 'is accessible inside nodes' do
      assert_equal({"context" => {"person_name" => "Han Solo"}}, result)
    end

    describe 'inside edges' do
      let(:query_string) { "post(123) { comments { viewer_name_length } }"}
      it 'is accessible' do
        assert_equal 8, result["123"]["comments"]["viewer_name_length"]
      end
    end
  end

  describe 'parsing error' do
    let(:query_string) { "\n\n<< bogus >>"}

    it 'raises SyntaxError' do
      assert_raises(GraphQL::SyntaxError) { result }
    end

    it 'contains line an character number' do
      err = assert_raises(GraphQL::SyntaxError) { result }
      assert_match(/1, 1/, err.to_s)
    end

    it 'contains sample of text' do
      err = assert_raises(GraphQL::SyntaxError) { result }
      assert_includes(err.to_s, "<< bogus >>")
    end
  end
end