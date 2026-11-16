require_relative "test_helper"

# The :json formatter encodes each entry with Active Support's JSON encoder, through #to_json. When
# that encoder and the json gem disagree, as Active Support 7.2.3.2 and 8.0.5.2 and earlier do with
# json 3, every entry is dropped, and only Semantic Logger's internal logger (here,
# test/dummy/log/test.log) says why.
class JsonFormatterTest < Minitest::Test
  describe "the :json formatter" do
    it "writes an entry" do
      io       = StringIO.new
      appender = SemanticLogger.add_appender(io: io, formatter: :json)
      SemanticLogger["JsonFormatterTest"].info("Hello", user_id: 42, name: "Jack")
      SemanticLogger.flush

      entry = io.string.lines.map { |line| JSON.parse(line) }.find { |e| e["name"] == "JsonFormatterTest" }

      refute_nil entry, "Nothing was written: see the internal logger's errors in test/dummy/log/test.log"
      assert_equal "Hello", entry["message"]
      assert_equal({"user_id" => 42, "name" => "Jack"}, entry["payload"])
    ensure
      SemanticLogger.remove_appender(appender) if appender
    end
  end
end
