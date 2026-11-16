# frozen_string_literal: true

# Hidden acceptance probe for the Tasklane benchmark app. The agent never
# sees this file; it checks the domain rules from benchmark/PROMPT.md
# through the public HTTP surface only.
#
# Run from inside the generated app, under its own bundle:
#   cd <app> && bundle exec rspec <mstack>/benchmark/probe/acceptance_spec.rb

require "json"
require "date"
require "tempfile"
require "rack"
require "rack/test"

ENV["RACK_ENV"] = "test"
PROBE_DB = Tempfile.create(["tasklane-probe", ".sqlite3"]).path
ENV["DATABASE_URL"] = "sqlite://#{PROBE_DB}"
abort "probe: rake db:migrate failed" unless system("bundle exec rake db:migrate", out: File::NULL)

PROBE_APP = begin
  built = Rack::Builder.parse_file("config.ru")
  built.is_a?(Array) ? built.first : built
end

RSpec.describe "Tasklane" do
  include Rack::Test::Methods

  def app
    PROBE_APP
  end

  def unique(base)
    @counter = (@counter || 0) + 1
    "#{base} #{Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)}#{@counter}"
  end

  def api(method, path, body = nil)
    args = body.nil? ? [path] : [path, JSON.generate(body), { "CONTENT_TYPE" => "application/json" }]
    public_send(method, *args)
    last_response.body.empty? ? nil : JSON.parse(last_response.body)
  end

  def create_list(name = unique("Probe"))
    api(:post, "/api/v1/lists", "name" => name).fetch("list")
  end

  def create_todo(slug, attrs = {})
    api(:post, "/api/v1/lists/#{slug}/todos", { "title" => "task" }.merge(attrs)).fetch("todo")
  end

  def titles(slug, query = "")
    api(:get, "/api/v1/lists/#{slug}/todos#{query}").fetch("todos").map { |todo| todo["title"] }
  end

  def open_total
    get "/healthz"
    last_response.body[/\Aok:(\d+)\z/, 1]&.to_i
  end

  describe "HTML" do
    it "redirects / to /lists" do
      get "/"
      expect(last_response.status).to be_between(301, 303)
      expect(last_response.headers["Location"]).to end_with("/lists")
    end

    it "serves healthz as ok:<open count>" do
      expect(open_total).to be_a(Integer)
    end

    it "puts the footer and Tailwind on every page" do
      slug = create_list["slug"]
      ["/lists", "/lists/#{slug}", "/trash"].each do |path|
        get path
        expect(last_response.status).to eq(200), path
        expect(last_response.body).to include("Tasklane · built with mstack"), path
        expect(last_response.body).to include("cdn.tailwindcss.com"), path
      end
    end

    it "creates a list from the form and redirects to its slug" do
      post "/lists", "name" => "  Weekend Errands!  "
      expect(last_response.status).to be_between(301, 303)
      expect(last_response.headers["Location"]).to match(%r{/lists/weekend-errands(-\d+)?\z})
    end

    it "re-renders with 422 when the list name is blank" do
      post "/lists", "name" => "   "
      expect(last_response.status).to eq(422)
    end

    it "returns 404 for an unknown list" do
      get "/lists/no-such-list-anywhere"
      expect(last_response.status).to eq(404)
    end

    it "creates a todo from the form with comma-separated tags" do
      slug = create_list["slug"]
      post "/lists/#{slug}/todos", "title" => "Buy milk", "priority" => "urgent", "due_on" => "2031-01-02", "tags" => "Home, shop ,home"
      expect(last_response.status).to be_between(301, 303)
      todo = api(:get, "/api/v1/lists/#{slug}/todos").fetch("todos").first
      expect(todo).to include("title" => "Buy milk", "priority" => "urgent", "due_on" => "2031-01-02", "tags" => %w[home shop])
    end

    it "re-renders the list with 422 for an invalid todo" do
      slug = create_list["slug"]
      post "/lists/#{slug}/todos", "title" => "x", "priority" => "high"
      expect(last_response.status).to eq(422)
      expect(titles(slug)).to be_empty
    end

    it "escapes user-supplied text" do
      slug = create_list["slug"]
      create_todo(slug, "title" => "<script>alert('probe')</script>")
      get "/lists/#{slug}"
      expect(last_response.body).not_to include("<script>alert('probe')</script>")
      expect(last_response.body).to include("&lt;script&gt;")
    end

    it "marks overdue todos on the list page" do
      slug = create_list["slug"]
      create_todo(slug, "title" => "late one", "due_on" => (Date.today - 3).iso8601)
      get "/lists/#{slug}"
      expect(last_response.body).to match(/overdue/i)
    end

    it "toggles, soft-deletes and restores through the HTML buttons" do
      slug = create_list["slug"]
      id = create_todo(slug, "title" => "cycle me")["id"]

      post "/todos/#{id}/toggle"
      expect(last_response.headers["Location"]).to end_with("/lists/#{slug}")
      expect(titles(slug, "?status=done")).to eq(["cycle me"])

      post "/todos/#{id}/delete"
      expect(titles(slug, "?status=all")).to be_empty
      get "/trash"
      expect(last_response.body).to include("cycle me")

      post "/todos/#{id}/restore"
      expect(last_response.headers["Location"]).to end_with("/trash")
      expect(titles(slug, "?status=all")).to eq(["cycle me"])
    end

    it "filters the list page by status" do
      slug = create_list["slug"]
      create_todo(slug, "title" => "still-open-probe")
      done = create_todo(slug, "title" => "finished-probe")
      api(:patch, "/api/v1/todos/#{done['id']}", "done" => true)

      get "/lists/#{slug}"
      expect(last_response.body).to include("still-open-probe")
      expect(last_response.body).not_to include("finished-probe")
      get "/lists/#{slug}?status=done"
      expect(last_response.body).to include("finished-probe")
      expect(last_response.body).not_to include("still-open-probe")
    end
  end

  describe "lists" do
    it "derives slugs: lowercase, runs of non-alphanumerics to one dash, trimmed" do
      name = unique("  My -- Shopping & Stuff!! ")
      slug = create_list(name)["slug"]
      expect(slug).to match(/\A[a-z0-9]+(-[a-z0-9]+)*\z/)
      expect(slug).to include("shopping-stuff")
      expect(slug.length).to be <= 40
    end

    it "truncates slugs to 40 characters" do
      expect(create_list("a" * 60)["slug"].length).to be <= 40
    end

    it "suffixes duplicate slugs with -2, -3" do
      name = unique("Dupe").gsub(/[^A-Za-z0-9 ]/, "")
      first = create_list(name)["slug"]
      expect(create_list(name)["slug"]).to eq("#{first}-2")
      expect(create_list(name)["slug"]).to eq("#{first}-3")
    end

    it "falls back to the slug 'list' when the name has no alphanumerics" do
      expect(create_list("!!!")["slug"]).to match(/\Alist(-\d+)?\z/)
    end

    it "rejects blank and overlong names with the validation error shape" do
      body = api(:post, "/api/v1/lists", "name" => " ")
      expect(last_response.status).to eq(422)
      expect(body.dig("error", "code")).to eq("validation_failed")
      expect(body.dig("error", "fields")).to be_a(Hash)

      api(:post, "/api/v1/lists", "name" => "n" * 61)
      expect(last_response.status).to eq(422)
    end

    it "lists every list ordered by name with open counts" do
      slug = create_list["slug"]
      create_todo(slug)
      lists = api(:get, "/api/v1/lists").fetch("lists")
      expect(lists.map { |list| list["name"] }).to eq(lists.map { |list| list["name"] }.sort)
      expect(lists.find { |list| list["slug"] == slug }).to include("open_count" => 1)
    end
  end

  describe "todos" do
    let(:slug) { create_list["slug"] }

    it "returns the documented todo shape with defaults" do
      todo = create_todo(slug, "title" => "  shaped  ")
      expect(last_response.status).to eq(201)
      expect(todo).to include("title" => "shaped", "priority" => "normal", "done" => false, "due_on" => nil,
                              "overdue" => false, "tags" => [], "list" => slug)
      expect(todo["id"]).to be_a(Integer)
    end

    it "accepts only low, normal and urgent as priority" do
      %w[low normal urgent].each { |priority| create_todo(slug, "priority" => priority) }
      body = api(:post, "/api/v1/lists/#{slug}/todos", "title" => "t", "priority" => "high")
      expect(last_response.status).to eq(422)
      expect(body.dig("error", "fields")).to have_key("priority")
    end

    it "validates the title length" do
      api(:post, "/api/v1/lists/#{slug}/todos", "title" => "   ")
      expect(last_response.status).to eq(422)
      api(:post, "/api/v1/lists/#{slug}/todos", "title" => "t" * 121)
      expect(last_response.status).to eq(422)
      api(:post, "/api/v1/lists/#{slug}/todos", "title" => "t" * 120)
      expect(last_response.status).to eq(201)
    end

    it "orders by priority, then due date with undated last, then id" do
      create_todo(slug, "title" => "low-dated", "priority" => "low", "due_on" => "2030-01-01")
      create_todo(slug, "title" => "normal-undated", "priority" => "normal")
      create_todo(slug, "title" => "urgent-late", "priority" => "urgent", "due_on" => "2030-06-01")
      create_todo(slug, "title" => "normal-dated", "priority" => "normal", "due_on" => "2030-03-01")
      create_todo(slug, "title" => "urgent-undated", "priority" => "urgent")
      create_todo(slug, "title" => "urgent-early", "priority" => "urgent", "due_on" => "2030-02-01")
      create_todo(slug, "title" => "normal-undated-2", "priority" => "normal")

      expect(titles(slug)).to eq(%w[urgent-early urgent-late urgent-undated normal-dated normal-undated normal-undated-2 low-dated])
    end

    it "computes overdue from the due date and the done flag" do
      late = create_todo(slug, "due_on" => (Date.today - 1).iso8601)
      today = create_todo(slug, "due_on" => Date.today.iso8601)
      expect(late["overdue"]).to be(true)
      expect(today["overdue"]).to be(false)
      expect(api(:patch, "/api/v1/todos/#{late['id']}", "done" => true).dig("todo", "overdue")).to be(false)
    end

    it "updates fields with PATCH and leaves the others alone" do
      todo = create_todo(slug, "title" => "before", "priority" => "low", "tags" => %w[a b])
      updated = api(:patch, "/api/v1/todos/#{todo['id']}", "title" => "after", "due_on" => "2032-12-31").fetch("todo")
      expect(last_response.status).to eq(200)
      expect(updated).to include("title" => "after", "priority" => "low", "due_on" => "2032-12-31", "tags" => %w[a b])
    end

    it "rejects an invalid PATCH without changing the todo" do
      todo = create_todo(slug, "title" => "stable")
      api(:patch, "/api/v1/todos/#{todo['id']}", "priority" => "high", "title" => "changed")
      expect(last_response.status).to eq(422)
      expect(titles(slug)).to eq(["stable"])
    end
  end

  describe "tags" do
    let(:slug) { create_list["slug"] }

    it "normalizes, deduplicates and sorts tag names" do
      todo = create_todo(slug, "tags" => [" Work ", "work", "URGENT-stuff", "alpha"])
      expect(todo["tags"]).to eq(%w[alpha urgent-stuff work])
    end

    it "allows 5 tags and rejects a sixth" do
      create_todo(slug, "tags" => %w[a b c d e])
      expect(last_response.status).to eq(201)
      body = api(:post, "/api/v1/lists/#{slug}/todos", "title" => "t", "tags" => %w[a b c d e f])
      expect(last_response.status).to eq(422)
      expect(body.dig("error", "code")).to eq("validation_failed")
    end

    it "rejects a tag longer than 20 characters" do
      api(:post, "/api/v1/lists/#{slug}/todos", "title" => "t", "tags" => ["x" * 21])
      expect(last_response.status).to eq(422)
    end

    it "replaces the whole tag set on PATCH" do
      todo = create_todo(slug, "tags" => %w[one two])
      expect(api(:patch, "/api/v1/todos/#{todo['id']}", "tags" => ["three"]).dig("todo", "tags")).to eq(["three"])
    end
  end

  describe "filters" do
    let(:slug) { create_list["slug"] }

    before do
      create_todo(slug, "title" => "Write Report", "tags" => %w[work])
      done = create_todo(slug, "title" => "File report copy", "tags" => %w[work archive])
      api(:patch, "/api/v1/todos/#{done['id']}", "done" => true)
      create_todo(slug, "title" => "Water plants", "tags" => %w[home])
    end

    it "defaults to open todos" do
      expect(titles(slug)).to contain_exactly("Write Report", "Water plants")
    end

    it "filters by status" do
      expect(titles(slug, "?status=done")).to eq(["File report copy"])
      expect(titles(slug, "?status=all").size).to eq(3)
    end

    it "filters by tag, case-insensitively" do
      expect(titles(slug, "?tag=WORK&status=all")).to contain_exactly("Write Report", "File report copy")
    end

    it "searches titles case-insensitively" do
      expect(titles(slug, "?q=REPORT&status=all")).to contain_exactly("Write Report", "File report copy")
    end

    it "combines filters" do
      expect(titles(slug, "?q=report&tag=work")).to eq(["Write Report"])
    end
  end

  describe "soft delete" do
    let(:slug) { create_list["slug"] }

    it "hides a deleted todo everywhere and drops it from the counts" do
      keep = create_todo(slug, "title" => "keeper")
      gone = create_todo(slug, "title" => "goner", "tags" => %w[x])
      before = open_total

      api(:delete, "/api/v1/todos/#{gone['id']}")
      expect(last_response.status).to eq(204)
      expect(last_response.body).to be_empty
      expect(titles(slug, "?status=all")).to eq(["keeper"])
      expect(titles(slug, "?tag=x&status=all")).to be_empty
      expect(open_total).to eq(before - 1)
      expect(api(:get, "/api/v1/lists").fetch("lists").find { |list| list["slug"] == slug }["open_count"]).to eq(1)
      expect(keep["id"]).not_to eq(gone["id"])
    end

    it "treats a deleted todo as not found for PATCH and DELETE, and restores it" do
      todo = create_todo(slug, "title" => "phoenix")
      api(:delete, "/api/v1/todos/#{todo['id']}")

      api(:patch, "/api/v1/todos/#{todo['id']}", "title" => "nope")
      expect(last_response.status).to eq(404)
      api(:delete, "/api/v1/todos/#{todo['id']}")
      expect(last_response.status).to eq(404)

      restored = api(:post, "/api/v1/todos/#{todo['id']}/restore")
      expect(last_response.status).to eq(200)
      expect(restored.dig("todo", "title")).to eq("phoenix")
      expect(titles(slug)).to eq(["phoenix"])
    end
  end

  describe "API errors" do
    it "answers 404 in the error shape for unknown lists, todos and routes" do
      ["/api/v1/lists/no-such-list-anywhere/todos", "/api/v1/nonsense"].each do |path|
        body = api(:get, path)
        expect(last_response.status).to eq(404), path
        expect(body.dig("error", "code")).to eq("not_found"), path
        expect(body.dig("error", "message")).to be_a(String), path
      end
      api(:patch, "/api/v1/todos/999999999", "title" => "x")
      expect(last_response.status).to eq(404)
    end

    it "answers 400 for a body that is not a JSON object" do
      post "/api/v1/lists", "not json at all", { "CONTENT_TYPE" => "application/json" }
      expect(last_response.status).to eq(400)
      expect(JSON.parse(last_response.body).dig("error", "code")).to eq("bad_request")

      post "/api/v1/lists", "[1,2]", { "CONTENT_TYPE" => "application/json" }
      expect(last_response.status).to eq(400)
    end
  end
end
